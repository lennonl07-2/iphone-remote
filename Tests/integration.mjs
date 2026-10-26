import assert from "node:assert/strict";
import net from "node:net";
import {spawn} from "node:child_process";
import {readFile,unlink} from "node:fs/promises";
import {randomBytes} from "node:crypto";
import {fileURLToPath} from "node:url";
const root=fileURLToPath(new URL("../",import.meta.url));
const base="http://127.0.0.1:8765";
const pause=ms=>new Promise(r=>setTimeout(r,ms));
let passed=0;
function check(value,message){assert.ok(value,message);console.log("PASS",message);passed++;}
function request(path,{method="GET",body,origin=base,host="127.0.0.1:8765",extra=""}={}){return new Promise((resolve,reject)=>{const socket=net.connect(8765,"127.0.0.1");let buffer="";socket.setTimeout(3000,()=>socket.destroy(new Error("HTTP timeout")));socket.on("error",reject);socket.on("data",d=>buffer+=d);socket.on("end",()=>{const [head,...tail]=buffer.split("\r\n\r\n");resolve({code:Number(head.split(" ")[1]),body:tail.join("\r\n\r\n"),head});});socket.on("connect",()=>{const text=body===undefined?"":JSON.stringify(body);socket.write(`${method} ${path} HTTP/1.1\r\nHost: ${host}\r\nOrigin: ${origin}\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(text)}\r\n${extra}\r\n${text}`);});});}
function encode(value,{masked=true,opcode=1}={}){const payload=Buffer.from(typeof value==="string"?value:JSON.stringify(value));const mask=randomBytes(4);let head=payload.length<126?Buffer.from([128|opcode,(masked?128:0)|payload.length]):Buffer.from([128|opcode,(masked?128:0)|126,payload.length>>8,payload.length&255]);return Buffer.concat([head,...(masked?[mask]:[]),masked?Buffer.from(payload.map((b,i)=>b^mask[i%4])):payload]);}
async function socket(){const sock=net.connect(8765,"127.0.0.1");let buffer=Buffer.alloc(0),upgraded=false,ended=false,queue=[],waiters=[];const deliver=v=>{if(waiters.length)waiters.shift()(v);else queue.push(v);};sock.on("error",()=>{});sock.on("close",()=>{ended=true;deliver({closed:true});});sock.on("data",data=>{buffer=Buffer.concat([buffer,data]);if(!upgraded){const end=buffer.indexOf("\r\n\r\n");if(end<0)return;check(buffer.subarray(0,end).toString().startsWith("HTTP/1.1 101"),"WebSocket handshake");buffer=buffer.subarray(end+4);upgraded=true;deliver({upgraded:true});}while(buffer.length>=2){let len=buffer[1]&127,off=2;if(len===126){if(buffer.length<4)return;len=buffer.readUInt16BE(2);off=4;}if(buffer.length<off+len)return;const opcode=buffer[0]&15,payload=buffer.subarray(off,off+len);buffer=buffer.subarray(off+len);deliver(opcode===1?JSON.parse(payload):{opcode,payload:payload.toString()});}});
 const next=()=>queue.length?Promise.resolve(queue.shift()):ended?Promise.resolve({closed:true}):new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(new Error("WS timeout")),3000);waiters.push(v=>{clearTimeout(t);resolve(v);});});
 sock.on("connect",()=>sock.write(`GET /ws HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nOrigin: ${base}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ${randomBytes(16).toString("base64")}\r\n\r\n`));await next();return{sock,next,send:(v,o)=>sock.write(encode(v,o)),close:()=>sock.destroy()};}
await unlink(root+"build/test-pin").catch(()=>{});
const process=spawn(root+"build/test-server",[root],{stdio:["ignore","pipe","pipe"]});let stderr="";process.stderr.on("data",d=>stderr+=d);
try{
 let pin;for(let i=0;i<60;i++){try{pin=await readFile(root+"build/test-pin","utf8");const r=await request("/");if(r.code===200)break;}catch{}await pause(100);}
 check(/^\d{6}$/.test(pin??""),"Temporary test PIN generated");
 let r=await request("/");check(r.code===200&&r.body.includes("viewport-fit=cover"),"HTTP serves iPhone interface");
 check(r.head.includes("frame-ancestors"),"CSP protects interface");
 for(const path of ["/app.js","/styles.css","/manifest.json","/icons/apple-touch-icon.png"]){r=await request(path);check(r.code===200,`Asset ${path}`);}
 check((await request("/",{host:"evil.example:8765"})).code===403,"Reject DNS rebinding Host");
 check((await request("/pair",{method:"POST",origin:"http://evil.example",body:{pin}})).code===403,"Reject cross-origin pairing");
 check((await request("/../../Sources/Security.swift")).code===404,"No path traversal");
 const unauth=await socket();unauth.send({type:"mouse_move",dx:100,dy:100});check((await unauth.next()).type==="auth_error","Reject unauthenticated control");unauth.close();
 r=await request("/pair",{method:"POST",body:{pin:"not-the-pin"}});check(r.code===403,"Reject incorrect PIN");
 r=await request("/pair",{method:"POST",body:{pin,name:"Integration fixture"}});check(r.code===200,`Pair and persist credential to Keychain (${r.body.includes("token")})`);const token=JSON.parse(r.body).token;check(Buffer.from(token,"base64").length===32,"256-bit random token");
 check((await request("/pair",{method:"POST",body:{pin}})).code===403,"PIN is single use");
 const invalid=await socket();invalid.send({type:"auth",token:"invalid"});check((await invalid.next()).type==="auth_error","Reject invalid token");invalid.close();
 const auth=await socket();auth.send({type:"auth",token});const ready=await auth.next();check(ready.type==="ready"&&typeof ready.accessibility==="boolean","Authenticate and report Accessibility");
 const other=await socket();other.send({type:"auth",token});check((await other.next()).type==="busy","Only one controller owns input");other.close();
 // No mouse or keyboard events are injected during automated tests.
 auth.send({type:"heartbeat"});const state=await auth.next();check(["status","error"].includes(state.type),"Authenticated heartbeat handled");
 auth.send("hello",{opcode:9});check((await auth.next()).opcode===10,"Ping responds with Pong");
 auth.send({type:"heartbeat"},{masked:false});check((await auth.next()).closed,"Reject unmasked client frame");auth.close();await pause(100);
 const fresh=await socket();fresh.send({type:"auth",token});check((await fresh.next()).type==="ready","Reconnect with saved token");
 const split=encode({type:"heartbeat"});fresh.sock.write(split.subarray(0,3));await pause(30);fresh.sock.write(split.subarray(3));check(["status","error"].includes((await fresh.next()).type),"TCP segmentation reassembled");fresh.close();
 console.log(`\n${passed} integration checks passed. No native input injected.`);
}catch(error){console.error(stderr);throw error;}finally{process.kill("SIGTERM");await new Promise(resolve=>{process.once("exit",resolve);setTimeout(resolve,1500);});await unlink(root+"build/test-pin").catch(()=>{});}
