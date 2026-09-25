import { startServer } from '../server.mjs';
const port=Number(process.argv[2]||8766);
const service=await startServer({port,host:'127.0.0.1',dataDir:null});
service.server.on('upgrade',request=>console.log('Native handshake Origin:',request.headers.origin ?? '(none)'));
