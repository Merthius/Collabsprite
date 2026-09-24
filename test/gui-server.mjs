// Manual two-process GUI test: loopback only, no saved artwork or invitations.
// Start with node test/gui-server.mjs; connect two installed Aseprite clients.
import { startServer } from '../server.mjs';

const service = await startServer({ port: 8765, host: '127.0.0.1', dataDir: null });
let previous = '';
const monitor = setInterval(() => {
  const report = [...service.rooms.values()].map(({ core, clients }) => ({
    revision: core.revision,
    clients: [...clients].map(c => ({ name: c.name, ...core.history(c.author) })),
    width: core.meta.width, height: core.meta.height,
    cels: [...core.cells.values()].map(c => {
      const colors = {}, sample = [];
      c.pixels.forEach((color, index) => {
        if (!color) return;
        const rgba = color.toString(16).padStart(8, '0');
        colors[rgba] = (colors[rgba] || 0) + 1;
        if (sample.length < 128) sample.push([index % core.meta.width, Math.floor(index / core.meta.width), rgba]);
      });
      return { layer: c.layer, frame: c.frame, colors, sample };
    }),
  }));
  const serialized = JSON.stringify(report);
  if (serialized !== previous) { console.log(serialized); previous = serialized; }
}, 200);
async function stop() { clearInterval(monitor); await service.close(); process.exit(0); }
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
