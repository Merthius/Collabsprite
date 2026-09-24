import { startServer } from '../server.mjs';
const service=await startServer({port:8766,host:'127.0.0.1',dataDir:null});
service.server.on('upgrade',request=>console.log('Native handshake Origin:',request.headers.origin ?? '(none)'));
