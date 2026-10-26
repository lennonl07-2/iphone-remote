"use strict";
const $ = id => document.getElementById(id);
const store = {get(k){try{return localStorage.getItem(k);}catch{return null;}},set(k,v){try{localStorage.setItem(k,v);return true;}catch{return false;}},remove(k){try{localStorage.removeItem(k);}catch{}}};
let token = store.get("remote-token"), ws = null, ready = false, retry = 0, reconnectTimer, heartbeatTimer;
let pending = {dx:0,dy:0,sx:0,sy:0}, animation = 0, noticeTimer;
const modifiers = new Set();
function notice(text, permanent=false){clearTimeout(noticeTimer);$("notice").textContent=text;$("notice").hidden=false;if(!permanent)noticeTimer=setTimeout(()=>$("notice").hidden=true,5500);}
function send(object){if(!ready || !ws || ws.readyState!==WebSocket.OPEN)return false;if(ws.bufferedAmount>16384){ws.close();return false;}ws.send(JSON.stringify(object));return true;}
function flush(){if(animation)cancelAnimationFrame(animation);animation=0;const p=pending;pending={dx:0,dy:0,sx:0,sy:0};if(p.dx||p.dy)send({type:"mouse_move",dx:p.dx,dy:p.dy});if(p.sx||p.sy)send({type:"scroll",dx:p.sx,dy:p.sy});}
function queue(dx,dy,scroll=false){if(!ready)return;pending[scroll?"sx":"dx"]+=dx;pending[scroll?"sy":"dy"]+=dy;if(!animation)animation=requestAnimationFrame(flush);}
function command(type,extra={}){flush();return send({type,...extra});}
function resetModifiers(){modifiers.clear();document.querySelectorAll("[data-mod]").forEach(b=>b.setAttribute("aria-pressed","false"));}
function key(key){command("key_press",{key,modifiers:[...modifiers]});resetModifiers();}
function typeText(text){if(!text)return;if(modifiers.size){for(const ch of text){if(/^[a-z0-9 .,;\x27/\\\[\]=`-]$/i.test(ch))key(ch===" "?"space":ch.toLowerCase());else notice("Usa una letra o una tecla especial para el atajo.");}resetModifiers();}else{let chunk="";for(const ch of text){if(chunk.length+ch.length>1024){command("text_input",{text:chunk});chunk="";}chunk+=ch;}if(chunk)command("text_input",{text:chunk});}}
function reconnect(){clearTimeout(reconnectTimer);if(document.hidden||!token)return;const delay=Math.min(15000,500*2**Math.min(retry++,5))+Math.random()*250;reconnectTimer=setTimeout(connect,delay);}
function connect(){clearTimeout(reconnectTimer);if(document.hidden||!token)return;if(ws&&(ws.readyState===0||ws.readyState===1))return;const socket=new WebSocket(`${location.protocol==="https:"?"wss:":"ws:"}//${location.host}/ws`);ws=socket;
 socket.onopen=()=>socket.send(JSON.stringify({type:"auth",token}));
 socket.onmessage=event=>{let msg;try{msg=JSON.parse(event.data);}catch{return;}if(socket!==ws)return;
  if(msg.type==="ready"){ready=true;retry=0;$("pairing").hidden=true;$("status").textContent=`🟢 Conectado a: ${msg.name}`;clearInterval(heartbeatTimer);heartbeatTimer=setInterval(()=>send({type:"heartbeat"}),1000);if(!msg.accessibility)notice("Activa Accesibilidad para iPhone Remote en el Mac.",true);else $("notice").hidden=true;}
  if(msg.type==="status"&&msg.accessibility&&$("notice").textContent.startsWith("Activa Accesibilidad"))$("notice").hidden=true;
  if(msg.type==="auth_error"){token=null;store.remove("remote-token");$("pairing").hidden=false;notice("Empareja de nuevo desde el menú del Mac.");socket.close();}
  if(msg.type==="busy")notice(msg.message);
  if(msg.type==="error")notice(msg.message);
 };
 socket.onclose=()=>{if(socket!==ws)return;ready=false;ws=null;clearInterval(heartbeatTimer);resetGesture(false);resetModifiers();pending={dx:0,dy:0,sx:0,sy:0};$("status").textContent="🔴 Sin conexión · reconectando…";if(!token)$("status").textContent="🔴 Sin conexión";reconnect();};
 socket.onerror=()=>socket.close();
}
$("pairForm").addEventListener("submit",async event=>{event.preventDefault();const button=event.target.querySelector("button");button.disabled=true;try{const result=await fetch("/pair",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({pin:$("pin").value,name:/iPhone/.test(navigator.userAgent)?"iPhone":"Control web"})});const data=await result.json();if(!result.ok)throw new Error(data.error);token=data.token;if(!store.set("remote-token",token))notice("Safari no permite guardar la credencial: deberás emparejar al cerrar.");$("pin").value="";$("pairing").hidden=true;connect();}catch(error){notice(error.message);}finally{button.disabled=false;}});
$("pairing").hidden=!!token;
$("settingsToggle").onclick=()=>$("settings").hidden=!$("settings").hidden;
$("forget").onclick=()=>{command("release_all");token=null;store.remove("remote-token");if(ws)ws.close();$("pairing").hidden=false;$("settings").hidden=true;notice("Para revocar la autorización, usa Dispositivos autorizados en el Mac.");};
$("speed").value=store.get("remote-speed")||"1";$("speed").onchange=()=>store.set("remote-speed",$("speed").value);
$("natural").checked=store.get("remote-natural")!=="false";$("natural").onchange=()=>store.set("remote-natural",String($("natural").checked));
$("leftClick").onclick=()=>command("left_click");$("rightClick").onclick=()=>command("right_click");
$("shortcutsToggle").onclick=()=>$("shortcuts").hidden=!$("shortcuts").hidden;
document.querySelectorAll("[data-shortcut]").forEach(b=>b.onclick=()=>command("key_press",{key:b.dataset.shortcut,modifiers:["meta"]}));
document.querySelectorAll("[data-media]").forEach(b=>b.onclick=()=>command("media_command",{command:b.dataset.media}));
// Touch Events preserve two-finger identity and work on iPhone Safari.
const pad=$("trackpad");let gesture=null,holdTimer,tapTimer,lastTap=0;
function center(touches){const t=Array.from(touches);return{x:t.reduce((n,v)=>n+v.clientX,0)/t.length,y:t.reduce((n,v)=>n+v.clientY,0)/t.length};}
function resetGesture(release=true){clearTimeout(holdTimer);clearTimeout(tapTimer);lastTap=0;if(release&&gesture?.dragging)command("mouse_up");gesture=null;pad.classList.remove("dragging");$("gestureHint").textContent="DESLIZA PARA MOVER";}
function startDrag(){if(!gesture||gesture.max!==1||gesture.moved||!ready)return;clearTimeout(tapTimer);gesture.dragging=true;command("mouse_down");pad.classList.add("dragging");$("gestureHint").textContent="ARRASTRANDO";}
pad.addEventListener("touchstart",event=>{event.preventDefault();if(!ready)return;const point=center(event.touches);if(!gesture){const now=performance.now();const second=lastTap>0&&now-lastTap<280;gesture={start:point,last:point,time:now,lastTime:now,max:event.touches.length,moved:false,dragging:false,second};if(second){clearTimeout(tapTimer);}if(event.touches.length===1)holdTimer=setTimeout(startDrag,second?230:380);}else{clearTimeout(holdTimer);if(gesture.dragging){command("mouse_up");gesture.dragging=false;pad.classList.remove("dragging");}gesture.max=Math.max(gesture.max,event.touches.length);gesture.last=point;gesture.start=point;}},{passive:false});
pad.addEventListener("touchmove",event=>{event.preventDefault();if(!gesture||!ready)return;const g=gesture,p=center(event.touches),now=performance.now();const travel=Math.hypot(p.x-g.start.x,p.y-g.start.y);if(!g.moved&&travel>4){g.moved=true;clearTimeout(holdTimer);if(g.second&&g.max===1&&!g.dragging){g.dragging=true;command("mouse_down");pad.classList.add("dragging");}}
 if(!g.moved&&!g.dragging)return;
 const dx=p.x-g.last.x,dy=p.y-g.last.y,dt=Math.max(8,now-g.lastTime);g.last=p;g.lastTime=now;
 if(g.max===1&&event.touches.length===1){const velocity=Math.hypot(dx,dy)/dt;const gain=Number($("speed").value)*(0.72+Math.min(1.8,velocity*0.65));queue(dx*gain,dy*gain);}else if(g.max===2&&event.touches.length===2){const direction=$("natural").checked?1:-1;queue(dx*direction,dy*direction,true);}
},{passive:false});
pad.addEventListener("touchend",event=>{event.preventDefault();clearTimeout(holdTimer);if(!gesture)return;if(event.touches.length){gesture.last=center(event.touches);return;}const g=gesture;flush();if(g.dragging)command("mouse_up");else if(!g.moved&&performance.now()-g.time<350){if(g.max===2){clearTimeout(tapTimer);lastTap=0;command("right_click");}else if(g.max===1){if(g.second){clearTimeout(tapTimer);lastTap=0;command("double_click");}else{lastTap=performance.now();tapTimer=setTimeout(()=>{lastTap=0;command("left_click");},280);}}}gesture=null;pad.classList.remove("dragging");$("gestureHint").textContent="DESLIZA PARA MOVER";},{passive:false});
pad.addEventListener("touchcancel",()=>resetGesture());
pad.addEventListener("contextmenu",e=>e.preventDefault());
// Sentinel allows iOS to emit backward deletion even when no local text is retained.
const typing=$("typing"),sentinel="\u200b";let composing=false;
function resetTyping(){typing.value=sentinel;typing.setSelectionRange(1,1);}
resetTyping();
$("keyboardToggle").onclick=()=>{const show=$("keyboardPanel").hidden;$("keyboardPanel").hidden=!show;document.body.classList.toggle("keyboard",show);if(show){resetTyping();typing.focus();}else{typing.blur();resetModifiers();}};
document.querySelectorAll(".keybar button").forEach(b=>{b.addEventListener("pointerdown",e=>e.preventDefault());b.onclick=()=>{if(b.dataset.mod){const m=b.dataset.mod;if(modifiers.has(m))modifiers.delete(m);else modifiers.add(m);b.setAttribute("aria-pressed",String(modifiers.has(m)));}else key(b.dataset.key);typing.focus();};});
typing.addEventListener("compositionstart",()=>composing=true);
typing.addEventListener("compositionend",()=>{composing=false;typeText(typing.value.replaceAll(sentinel,""));resetTyping();});
typing.addEventListener("beforeinput",event=>{if(composing||event.isComposing||event.inputType==="insertCompositionText")return;if(event.inputType==="deleteContentBackward"){event.preventDefault();key("delete");resetTyping();}else if(event.inputType==="insertLineBreak"||event.inputType==="insertParagraph"){event.preventDefault();key("enter");resetTyping();}else if(event.inputType.startsWith("insert")&&event.data!==null){event.preventDefault();typeText(event.data);resetTyping();}});
typing.addEventListener("input",()=>{if(!composing){typeText(typing.value.replaceAll(sentinel,""));resetTyping();}});
typing.addEventListener("paste",event=>{event.preventDefault();typeText(event.clipboardData.getData("text/plain"));resetTyping();});
typing.addEventListener("keydown",event=>{const names={Escape:"esc",Tab:"tab",ArrowLeft:"left",ArrowRight:"right",ArrowUp:"up",ArrowDown:"down"};if(names[event.key]){event.preventDefault();key(names[event.key]);}else if((event.metaKey||event.ctrlKey||event.altKey)&&event.key.length===1){event.preventDefault();command("key_press",{key:event.key.toLowerCase(),modifiers:[event.metaKey?"meta":null,event.ctrlKey?"ctrl":null,event.altKey?"alt":null,event.shiftKey?"shift":null].filter(Boolean)});}});
function suspend(){clearTimeout(reconnectTimer);clearInterval(heartbeatTimer);resetGesture();command("release_all");resetModifiers();if(ws)ws.close();}
document.addEventListener("visibilitychange",()=>{if(document.hidden)suspend();else connect();});
window.addEventListener("pagehide",suspend);window.addEventListener("pageshow",()=>{if(!document.hidden)connect();});window.addEventListener("online",()=>{retry=0;connect();});
function viewport(){document.documentElement.style.setProperty("--app-height",`${window.visualViewport?.height||window.innerHeight}px`);}
window.visualViewport?.addEventListener("resize",viewport);window.addEventListener("resize",viewport);viewport();connect();
