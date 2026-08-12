import { readFile } from "node:fs/promises";
import { statfs } from "node:fs/promises";
import { createServer } from "node:http";
import { connect } from "node:net";

const host = process.env.DASHBOARD_HOST ?? "127.0.0.1";
const port = Number(process.env.DASHBOARD_PORT ?? "8080");
const index = await readFile(new URL("index.html", import.meta.url));

const services = [
  { id: "home-assistant", name: "Home Assistant", host: "127.0.0.1", port: 8123 },
  { id: "memos", name: "Memos", host: "127.0.0.1", port: 5230 },
  { id: "jellyfin", name: "Jellyfin", host: "127.0.0.1", port: 8096 },
  { id: "prowlarr", name: "Prowlarr", host: "127.0.0.1", port: 9696 },
  { id: "qbittorrent", name: "qBittorrent", host: "127.0.0.1", port: 8082 },
  { id: "trilium", name: "Trilium", host: "127.0.0.1", port: 11000 },
  { id: "open-webui", name: "Balaur AI", host: "127.0.0.1", port: 3000 },
  { id: "fastflowlm", name: "FastFlowLM", host: "127.0.0.1", port: 8081 },
];

let previousCpu: { idle: number; total: number } | undefined;

async function cpuUsage(): Promise<number | null> {
  const stat = await readFile("/proc/stat", "utf8");
  const values = stat.split("\n", 1)[0].trim().split(/\s+/).slice(1).map(Number);
  const idle = values[3] + (values[4] ?? 0);
  const total = values.reduce((sum, value) => sum + value, 0);
  const current = { idle, total };

  if (!previousCpu) {
    previousCpu = current;
    return null;
  }

  const elapsed = total - previousCpu.total;
  const idleElapsed = idle - previousCpu.idle;
  previousCpu = current;
  return elapsed > 0 ? Math.round((1 - idleElapsed / elapsed) * 1000) / 10 : 0;
}

async function memoryUsage(): Promise<{ used: number; total: number; percent: number }> {
  const memory = await readFile("/proc/meminfo", "utf8");
  const values = new Map(
    memory.trim().split("\n").map((line) => {
      const [key, value] = line.split(/:\s+/);
      return [key, Number.parseInt(value, 10) * 1024];
    }),
  );
  const total = values.get("MemTotal") ?? 0;
  const available = values.get("MemAvailable") ?? 0;
  const used = total - available;
  return { used, total, percent: total ? Math.round((used / total) * 1000) / 10 : 0 };
}

const disks = [
  { id: "os", name: "OS", path: "/" },
  { id: "app-data", name: "Application data", path: "/srv/app-data" },
  { id: "personal", name: "Personal", path: "/srv/personal" },
  { id: "media-ssd0", name: "Media SSD 0", path: "/srv/media/ssd0" },
  { id: "media-ssd1", name: "Media SSD 1", path: "/srv/media/ssd1" },
];

type DiskUsage = (typeof disks)[number] & {
  mounted: boolean;
  used: number;
  total: number;
  percent: number;
};

async function diskUsage(): Promise<DiskUsage[]> {
  const mountInfo = await readFile("/proc/self/mountinfo", "utf8");
  const mountedPaths = new Set(mountInfo.trim().split("\n").map((line) => line.split(" ")[4]));

  return Promise.all(disks.map(async (disk) => {
    if (!mountedPaths.has(disk.path)) {
      return { ...disk, mounted: false, used: 0, total: 0, percent: 0 };
    }

    const filesystem = await statfs(disk.path);
    const total = filesystem.blocks * filesystem.bsize;
    const available = filesystem.bavail * filesystem.bsize;
    const used = total - available;
    return {
      ...disk,
      mounted: true,
      used,
      total,
      percent: total ? Math.round((used / total) * 1000) / 10 : 0,
    };
  }));
}

function serviceOnline(service: (typeof services)[number]): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ host: service.host, port: service.port });
    const finish = (online: boolean) => {
      socket.destroy();
      resolve(online);
    };
    socket.setTimeout(700);
    socket.once("connect", () => finish(true));
    socket.once("timeout", () => finish(false));
    socket.once("error", () => finish(false));
  });
}

async function status() {
  const [cpu, memory, disks, serviceStates, uptime] = await Promise.all([
    cpuUsage(),
    memoryUsage(),
    diskUsage(),
    Promise.all(services.map(serviceOnline)),
    readFile("/proc/uptime", "utf8"),
  ]);

  return {
    host: "balaur",
    timestamp: new Date().toISOString(),
    uptime: Math.floor(Number.parseFloat(uptime) || 0),
    cpu,
    memory,
    disks,
    services: services.map(({ id, name }, index) => ({ id, name, online: serviceStates[index] })),
  };
}

const server = createServer(async (request, response) => {
  try {
    if (request.method === "GET" && request.url === "/") {
      response.writeHead(200, {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-cache",
        "Content-Security-Policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
      });
      response.end(index);
      return;
    }

    if (request.method === "GET" && request.url === "/api/status") {
      response.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
      response.end(JSON.stringify(await status()));
      return;
    }

    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found\n");
  } catch (error) {
    console.error(error);
    response.writeHead(500, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    response.end(JSON.stringify({ error: "Status unavailable" }));
  }
});

server.listen(port, host, () => console.log(`Dashboard listening on http://${host}:${port}`));
