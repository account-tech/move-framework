import { Transaction } from '@mysten/sui/transactions';
import { client, keypair, getId } from './utils.js';

export async function initExtensions(): Promise<boolean> {
    console.log("\n🔧 Initializing extensions...");
    try {
        const tx = new Transaction();
        tx.setGasBudget(100000000);

        const pkg = getId("account_extensions");

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("account_protocol"),
                tx.pure.address(getId("account_protocol")),
                tx.pure.u64(1),
            ],
        });

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("account_actions"),
                tx.pure.address(getId("account_actions")),
                tx.pure.u64(1),
            ],
        });

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("account_multisig"),
                tx.pure.address(getId("account_multisig")),
                tx.pure.u64(1),
            ],
        });

        tx.moveCall({
            target: `${pkg}::extensions::add`,
            arguments: [
                tx.object(getId("extensions::Extensions")),
                tx.object(getId("extensions::AdminCap")),
                tx.pure.string("account_dao"),
                tx.pure.address(getId("account_dao")),
                tx.pure.u64(1),
            ],
        });

        const result = await client.signAndExecuteTransaction({
            signer: keypair,
            transaction: tx,
            options: {
                showObjectChanges: true,
                showEffects: true,
            },
            requestType: "WaitForLocalExecution"
        });

        if (result.effects?.status?.status === "success") {
            console.log("✅ Core dependencies initialized successfully");
            return true;
        } else {
            console.error("❌ Failed to initialize core dependencies:", result.effects?.status?.error);
            return false;
        }
    } catch (error) {
        console.error("❌ Failed to initialize core dependencies:", error);
        return false;
    }
}