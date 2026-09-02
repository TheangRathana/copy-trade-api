import type { z } from "zod";
import type { masterPositionSchema, masterStateSchema } from "./master.schema.js";
export type MasterPosition = z.infer<typeof masterPositionSchema>;
export type MasterState = z.infer<typeof masterStateSchema>;
//# sourceMappingURL=master.types.d.ts.map