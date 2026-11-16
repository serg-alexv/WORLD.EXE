import http from 'node:http';
import { timingSafeEqual,createHash } from 'node:crypto';
import { GameboxHost } from './host.mjs';
import { fields, GateError, requireThat } from './contracts.mjs';
const digest=s=>createHash('sha256').update(s).digest();
function bearer(req){const h=req.headers.authorization;requireThat(typeof h==='string' && /^Bearer [A-Za-z0-9_-]{32,128}$/.test(h),'authorization_required',401);return h.slice(7);}
async function body(req,limit){
  requireThat(req.headers['content-type']==='application/json','json_required',415);
  if(req.headers['content-length'])requireThat(Number(req.headers['content-length'])<=limit,'body_too_large',413);
  const chunks=[];let size=0;
  for await(const chunk of req){size+=chunk.length;requireThat(size<=limit,'body_too_large',413);chunks.push(chunk);}
  try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw new GateError('invalid_json');}
}

/** Loopback development transport with authenticated SSE. Never a public deployment endpoint. */
export async function startServer(config,{operatorToken,control,now,autoTick=true}={}){
  requireThat(typeof operatorToken==='string' && /^[A-Za-z0-9_-]{32,128}$/.test(operatorToken),'operator_token_required');
  const operatorDigest=digest(operatorToken),host=new GameboxHost(config,{control,now}),streams=new Set();
  let requests=0,windowStart=Date.now(),timer;
  const server=http.createServer(async(req,res)=>{
    const reply=(status,data)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'});res.end(JSON.stringify(data));};
    const admin=()=>requireThat(timingSafeEqual(digest(bearer(req)),operatorDigest),'operator_required',403);
    try{
      requireThat(['127.0.0.1','::ffff:127.0.0.1'].includes(req.socket.remoteAddress),'loopback_only',403);
      requireThat(!req.headers.origin,'browser_origin_not_admitted',403);
      requireThat(req.headers.host===`127.0.0.1:${server.address().port}`,'invalid_host',403);
      if(Date.now()-windowStart>=1000){windowStart=Date.now();requests=0;}requireThat(++requests<=256,'request_budget',429);
      requireThat(req.url.length<=256 && !req.url.includes('?'),'invalid_route');
      if(req.method==='GET'&&req.url==='/healthz')return reply(200,{ok:true,mode:'local-reference'});
      if(req.method==='GET'&&req.url==='/v1/status'){admin();return reply(200,host.status());}
      if(req.method==='POST'&&req.url==='/v1/control'){admin();return reply(200,host.control.transition(await body(req,config.transport.bodyLimitBytes)));}
      if(req.method==='POST'&&req.url==='/v1/rooms'){admin();fields(await body(req,config.transport.bodyLimitBytes),[]);return reply(201,host.createRoom());}
      if(req.method==='DELETE'&&req.url==='/v1/session')return reply(200,host.revoke(bearer(req)));
      const m=/^\/v1\/rooms\/([0-9a-f-]{36})(?:\/(invitations|join|inputs|snapshot|signals|events))?$/.exec(req.url);
      requireThat(m,'not_found',404);const [,id,action]=m;
      if(req.method==='DELETE'&&!action){admin();host.closeRoom(id);return reply(200,{closed:true});}
      if(req.method==='POST'&&action==='invitations'){admin();fields(await body(req,config.transport.bodyLimitBytes),[]);return reply(201,host.invite(id));}
      if(req.method==='POST'&&action==='join')return reply(201,host.join(id,await body(req,config.transport.bodyLimitBytes)));
      if(req.method==='POST'&&action==='inputs')return reply(200,host.input(id,bearer(req),await body(req,config.transport.bodyLimitBytes)));
      if(req.method==='POST'&&action==='signals'){admin();return reply(200,host.signal(id,await body(req,config.transport.bodyLimitBytes)));}
      if(req.method==='GET'&&action==='snapshot')return reply(200,host.snapshot(id,bearer(req)));
      if(req.method==='GET'&&action==='events'){
        const token=bearer(req),s=host.session(token,id);
        requireThat(streams.size<64 && ![...streams].some(x=>x.playerID===s.playerID),'stream_limit',429);
        res.writeHead(200,{'content-type':'text/event-stream','cache-control':'no-store','x-content-type-options':'nosniff'});
        const stream={res,token,roomID:id,playerID:s.playerID};streams.add(stream);
        res.write(`event: snapshot\ndata: ${JSON.stringify(host.snapshot(id,token))}\n\n`);
        res.on('close',()=>streams.delete(stream));return;
      }
      throw new GateError('not_found',404);
    }catch(e){if(!res.headersSent)reply(e.status||500,{error:e instanceof GateError?e.code:'internal_error'});else res.end();}
  });
  server.requestTimeout=5000;server.headersTimeout=5000;server.keepAliveTimeout=1000;server.maxConnections=128;
  const pump=()=>{
    host.tick();
    for(const stream of streams){try{const data=host.snapshot(stream.roomID,stream.token);if(!stream.res.write(`event: snapshot\ndata: ${JSON.stringify(data)}\n\n`))stream.res.end();}catch{stream.res.end();}}
  };
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(config.transport.port,'127.0.0.1',resolve);});
  if(autoTick){timer=setInterval(pump,1000/config.simulation.tickHz);timer.unref();}
  return {host,pump,url:`http://127.0.0.1:${server.address().port}`,async close(){clearInterval(timer);for(const s of streams)s.res.end();server.closeAllConnections();await new Promise(r=>server.close(r));host.control.close();}};
}
