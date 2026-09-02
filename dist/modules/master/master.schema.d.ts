import { z } from "zod";
export declare const masterPositionSchema: z.ZodObject<{
    ticket: z.ZodUnion<readonly [z.ZodString, z.ZodNumber]>;
    symbol: z.ZodString;
    type: z.ZodEnum<{
        BUY: "BUY";
        SELL: "SELL";
    }>;
    volume: z.ZodNumber;
    openPrice: z.ZodNumber;
    stopLoss: z.ZodNumber;
    takeProfit: z.ZodNumber;
}, z.core.$strict>;
export declare const masterStateSchema: z.ZodObject<{
    accountNumber: z.ZodUnion<readonly [z.ZodString, z.ZodNumber]>;
    broker: z.ZodString;
    server: z.ZodString;
    positions: z.ZodArray<z.ZodObject<{
        ticket: z.ZodUnion<readonly [z.ZodString, z.ZodNumber]>;
        symbol: z.ZodString;
        type: z.ZodEnum<{
            BUY: "BUY";
            SELL: "SELL";
        }>;
        volume: z.ZodNumber;
        openPrice: z.ZodNumber;
        stopLoss: z.ZodNumber;
        takeProfit: z.ZodNumber;
    }, z.core.$strict>>;
    timestamp: z.ZodString;
}, z.core.$strict>;
//# sourceMappingURL=master.schema.d.ts.map