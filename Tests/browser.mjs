import assert from "node:assert/strict";
import http from "node:http";
import {spawn} from "node:child_process";
import {readFile,writeFile,mkdtemp,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {fileURLToPath} from "node:url";
const root=fileURLToPath(new URL("../",import.meta.url));
const profile=await mkdtemp(tmpdir()+"/iphoneremote-browser-");
const assets={"/":"index.html","/styles.css":"styles.css","/app.js":"app.js","/manifest.json":"manifest.json","/icons/apple-touch-icon.png":"icons/apple-touch-icon.png","/icons/icon-192.png":"icons/icon-192.png","/icons/icon-512.png":"icons/icon-512.png"};
const server=http.createServer(async(req,res)=>{const file=assets[req.url];if(!file){res.writeHead(404);res.end();return;}const mime=file.endsWith("js")?"text/javascript":file.endsWith("css")?"text/css":file.endsWith("png")?"image/png":file.endsWith("json")?"application/json":"text/html";res.writeHead(200,{"Content-Type":mime});res.end(await readFile(root+"Resources/Web/"+file));});await new Promise(r=>server.listen(0,"127.0.0.1",r));
const browser=spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",["--headless=new","--no-first-run","--no-default-browser-check","--disable-background-networking","--remote-debugging-port=0",`--user-data-dir=${profile}`,"about:blank"],{stdio:"ignore"});
const pause=ms=>new Promise(r=>setTimeout(r,ms));let socket;
try{
 let port;for(let i=0;i<80;i++){try{port=(await readFile(profile+"/DevToolsActivePort","utf8")).split("\n")[0];break;}catch{}await pause(100);}assert.ok(port,"Chrome remote debugging started");
 const pages=await(await fetch(`http://127.0.0.1:${port}/json/list`)).json();socket=new WebSocket(pages.find(p=>p.type==="page").webSocketDebuggerUrl);await new Promise(r=>socket.onopen=r);let id=0;const callbacks=new Map();const errors=[];
 socket.onmessage=e=>{const msg=JSON.parse(e.data);if(msg.id){const callback=callbacks.get(msg.id);callbacks.delete(msg.id);if(msg.error)callback.reject(new Error(JSON.stringify(msg.error)));else callback.resolve(msg.result);}else if(msg.method==="Runtime.exceptionThrown")errors.push(msg.params.exceptionDetails.text);};
 const call=(method,params={})=>new Promise((resolve,reject)=>{const next=++id;callbacks.set(next,{resolve,reject});socket.send(JSON.stringify({id:next,method,params}));});
 const evaluate=async expression=>{const result=await call("Runtime.evaluate",{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value;};
 await call("Runtime.enable");await call("Page.enable");await call("Emulation.setDeviceMetricsOverride",{width:393,height:852,deviceScaleFactor:3,mobile:true});await call("Emulation.setTouchEmulationEnabled",{enabled:true});
 await call("Page.addScriptToEvaluateOnNewDocument",{source:`localStorage.setItem("remote-token","test-fixture");window.sent=[];window.WebSocket=class{static OPEN=1;constructor(){this.readyState=0;this.bufferedAmount=0;setTimeout(()=>{this.readyState=1;this.onopen?.();},5);}send(text){const msg=JSON.parse(text);window.sent.push(msg);if(msg.type==="auth")setTimeout(()=>this.onmessage?.({data:JSON.stringify({type:"ready",name:"Mac de prueba",accessibility:true})}),5);}close(){this.readyState=3;this.onclose?.();}};window.touch=(type,points)=>{const event=new Event(type,{cancelable:true,bubbles:true});Object.defineProperty(event,"touches",{value:points.map(([x,y])=>({clientX:x,clientY:y}))});document.getElementById("trackpad").dispatchEvent(event);};`});
 await pause(1000);
 let navigation=await call("Page.navigate",{url:`http://127.0.0.1:${server.address().port}/`});
 if(navigation.errorText==="net::ERR_ABORTED"){await pause(1000);navigation=await call("Page.navigate",{url:`http://127.0.0.1:${server.address().port}/`});}
 if(navigation.errorText)console.log("Navigation diagnosis",await evaluate(`({url:location.href,html:document.documentElement.outerHTML.slice(0,1800)})`));
 assert.ok(!navigation.errorText,JSON.stringify(navigation));
 for(let i=0;i<100;i++){if(await evaluate(`!!document.getElementById("status")&&document.getElementById("status").textContent.includes("Conectado")`))break;await pause(100);}
 let count=0;async function check(expression,message){assert.ok(await evaluate(expression),message);console.log("PASS",message);count++;}
 await check(`document.getElementById("status").textContent.includes("Conectado a: Mac de prueba")`,"Connected interface");
 await check(`document.documentElement.scrollWidth <= innerWidth`,"No horizontal overflow at iPhone width");
 await check(`document.getElementById("trackpad").getBoundingClientRect().height > 400`,"Trackpad uses most of screen");
 await evaluate(`sent=[];touch("touchstart",[[100,100]]);touch("touchmove",[[120,110]]);touch("touchend",[])`);await check(`sent.some(x=>x.type==="mouse_move"&&x.dx>0&&x.dy>0)`,"One finger moves cursor");
 await evaluate(`sent=[];touch("touchstart",[[100,100],[150,100]]);touch("touchmove",[[110,120],[160,120]]);touch("touchend",[])`);await check(`sent.some(x=>x.type==="scroll"&&x.dx===10&&x.dy===20)`,"Two-finger proportional scroll");
 await evaluate(`sent=[];touch("touchstart",[[100,100],[150,100]]);touch("touchend",[])`);await check(`sent.some(x=>x.type==="right_click")`,"Two-finger tap is right click");
 await evaluate(`sent=[];touch("touchstart",[[100,100]]);touch("touchend",[])`);await pause(310);await check(`sent.filter(x=>x.type==="left_click").length===1`,"Single tap produces one click");
 await evaluate(`sent=[];touch("touchstart",[[100,100]]);touch("touchend",[])`);await pause(70);await evaluate(`touch("touchstart",[[100,100]]);touch("touchend",[])`);await pause(310);await check(`sent.filter(x=>x.type==="double_click").length===1&&!sent.some(x=>x.type==="left_click")`,"Double tap has no extra single click");
 await evaluate(`sent=[];touch("touchstart",[[100,100]])`);await pause(420);await evaluate(`touch("touchmove",[[150,120]]);touch("touchend",[])`);await check(`sent.map(x=>x.type).filter(x=>x!=="heartbeat").join(",")==="mouse_down,mouse_move,mouse_up"`,"Long hold drag has balanced down/up");
 await evaluate(`sent=[];document.getElementById("keyboardToggle").click();document.getElementById("typing").dispatchEvent(new InputEvent("beforeinput",{inputType:"insertText",data:"mañana 🐱",cancelable:true}))`);await check(`sent.some(x=>x.type==="text_input"&&x.text==="mañana 🐱")`,"Unicode text preserved");
 await evaluate(`sent=[];document.getElementById("typing").dispatchEvent(new InputEvent("beforeinput",{inputType:"deleteContentBackward",cancelable:true}))`);await check(`sent.some(x=>x.type==="key_press"&&x.key==="delete")`,"Backspace on empty field");
 await evaluate(`sent=[];document.querySelector("[data-mod=meta]").click();document.getElementById("typing").dispatchEvent(new InputEvent("beforeinput",{inputType:"insertText",data:"c",cancelable:true}))`);await check(`sent.some(x=>x.type==="key_press"&&x.key==="c"&&x.modifiers.includes("meta"))`,"Command+C shortcut");
 await check(`document.querySelector("[data-mod=meta]").getAttribute("aria-pressed")==="false"`,"Modifier resets after shortcut");
 await evaluate(`sent=[];const t=document.getElementById("typing");t.dispatchEvent(new CompositionEvent("compositionstart"));t.value="\\u200b你好".replace("\\u200b","\u200b");t.dispatchEvent(new CompositionEvent("compositionend"));t.dispatchEvent(new InputEvent("input"))`);await check(`sent.filter(x=>x.type==="text_input").length===1&&sent.find(x=>x.type==="text_input").text==="你好"`,"Composition is sent once");
 await evaluate(`document.getElementById("keyboardToggle").click()`);
 const shot=await call("Page.captureScreenshot",{format:"png"});await writeFile(root+"build/iphone-preview.png",Buffer.from(shot.data,"base64"));
 assert.deepEqual(errors,[]);console.log(`PASS No browser JavaScript exceptions\n${count+1} browser checks passed. Screenshot: build/iphone-preview.png`);
}finally{socket?.close();browser.kill("SIGTERM");server.close();await pause(500);await rm(profile,{recursive:true,force:true});}
