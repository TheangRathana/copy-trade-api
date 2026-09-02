import { buildApp } from "./app.js";
const host = process.env.HOST ?? "127.0.0.1";
const port = Number(process.env.PORT ?? 4000);
const app = buildApp();
async function start() {
    try {
        if (!Number.isInteger(port) || port < 1 || port > 65_535) {
            throw new Error(`Invalid PORT value: ${process.env.PORT}`);
        }
        await app.listen({ host, port });
    }
    catch (error) {
        app.log.error(error, "Failed to start server");
        process.exit(1);
    }
}
void start();
//# sourceMappingURL=server.js.map