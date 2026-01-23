import { SuiObjectChange } from "@mysten/sui/client";
import * as fs from "fs";
import * as TOML from "@iarna/toml";
import * as path from "path";
import { IObjectInfo } from "./utils.js";
import { spawnSync } from "child_process";

interface Package {
	name: string;
	path: string;
	dependencies: string[];
	published?: boolean;
}

export class PackagePublisher {
	private readonly packages: Map<string, Package>;

	constructor() {
		this.packages = new Map();
	}

	private async confirmPublish(): Promise<boolean> {
		const readline = require("readline").createInterface({
			input: process.stdin,
			output: process.stdout
		});

		return new Promise((resolve) => {
			console.log("\x1b[33m\nWARNING: Publishing will update Published.toml (or Pub.<env>.toml) and ./src/data/*.json files.\x1b[0m");
			readline.question("Are you sure you want to continue? (y/n): ", (answer: string) => {
				readline.close();
				resolve(answer.toLowerCase() === "y");
			});
		});
	}

	private findMoveTomls(dir: string): string[] {
		const results: string[] = [];
		const items = fs.readdirSync(dir, { withFileTypes: true });

		for (const item of items) {
			const fullPath = path.join(dir, item.name);
			if (item.isDirectory()) {
				results.push(...this.findMoveTomls(fullPath));
			} else if (item.name === 'Move.toml') {
				results.push(fullPath);
			}
		}

		return results;
	}

	public loadPackages(packagesRoot: string) {
		const moveTomlPaths = this.findMoveTomls(packagesRoot);

		for (const moveTomlPath of moveTomlPaths) {
			const content = fs.readFileSync(moveTomlPath, 'utf8');
			const parsed = TOML.parse(content);

			if (!(parsed.package as any).name) continue;

			const dependencies: string[] = [];
			if (parsed.dependencies) {
				for (const [depName, depInfo] of Object.entries(parsed.dependencies)) {
					if (depInfo && typeof depInfo === 'object' && 'local' in depInfo) {
						dependencies.push(depName);
					}
				}
			}
			this.packages.set((parsed.package as any).name, {
				name: (parsed.package as any).name,
				path: path.dirname(moveTomlPath),
				dependencies,
				published: false
			});
		}
	}

	private getPublishOrder(): string[] {
		const visited = new Set<string>();
		const order: string[] = [];

		const visit = (packageName: string) => {
			if (visited.has(packageName)) return;
			visited.add(packageName);

			const pkg = this.packages.get(packageName);
			if (!pkg) return;

			for (const dep of pkg.dependencies) {
				visit(dep);
			}
			order.push(packageName);
		};

		for (const packageName of this.packages.keys()) {
			visit(packageName);
		}

		return order;
	}

	private parseJsonOutput(stdout: string, stderr: string): any {
		const combined = [stdout, stderr].filter(Boolean).join("\n").trim();
		if (!combined) {
			throw new Error("Empty output from sui publish command.");
		}

		const jsonCandidate = this.extractJsonCandidate(stdout) ?? this.extractJsonCandidate(stderr);
		if (!jsonCandidate) {
			throw new Error(`Could not find JSON in output: ${combined}`);
		}

		return JSON.parse(jsonCandidate);
	}

	private extractJsonCandidate(output: string): string | null {
		const text = (output || "").trim();
		if (!text) return null;

		const startIndexes: number[] = [];
		for (let i = 0; i < text.length; i++) {
			const char = text[i];
			if (char === "{" || char === "[") startIndexes.push(i);
		}

		for (let i = startIndexes.length - 1; i >= 0; i--) {
			const candidate = text.slice(startIndexes[i]);
			try {
				JSON.parse(candidate);
				return candidate;
			} catch {
				// try next candidate
			}
		}

		return null;
	}

	private runPublishCommand(packageInfo: Package): any {
		const cliPath = process.env.CLI_PATH!;
		const args = ["client", "publish", "--json", packageInfo.path];

		const result = spawnSync(cliPath, args, { encoding: "utf-8" });
		if (result.error) {
			throw result.error;
		}
		if (result.status !== 0) {
			throw new Error(result.stderr || result.stdout || "sui publish failed");
		}

		return this.parseJsonOutput(result.stdout || "", result.stderr || "");
	}

	private async publishPackage(packageInfo: Package): Promise<string> {
		console.log(`\n📦 Publishing package: ${packageInfo.name}`);

		// Publish package (CLI updates Published.toml or Pub.<env>.toml)
		console.log("Publishing...");
		const result = this.runPublishCommand(packageInfo);

		if (result.effects?.status?.status !== "success") {
			throw new Error(`Publish failed: ${result.effects?.status?.error}`);
		}

		const objectChanges = result.objectChanges || [];
		const packageId = objectChanges.find((item: SuiObjectChange) => item.type === 'published')?.packageId;

		if (!packageId) {
			throw new Error("Could not find package ID in publish result");
		}

		// Save publish info
		const objects: IObjectInfo[] = objectChanges.map((item: SuiObjectChange) => ({
			type: item.type === 'published' ? packageInfo.name : item.objectType,
			id: item.type === 'published' ? item.packageId : item.objectId
		}));

		const dataDir = path.join(__dirname, "./data");
		if (!fs.existsSync(dataDir)) {
			fs.mkdirSync(dataDir, { recursive: true });
		}
		fs.writeFileSync(
			`${dataDir}/${packageInfo.name.replace(/_/g, "-")}.json`,
			JSON.stringify(objects, null, 2)
		);

		console.log("\x1b[32m" + `\n✅ Successfully published ${packageInfo.name} at: ${packageId}` + "\x1b[0m");
		return packageId;
	}

	public async publishAll(): Promise<boolean> {
		if (this.packages.size === 0) {
			console.log("Packages not loaded");
			return false;
		}

		const confirmed = await this.confirmPublish();
		if (!confirmed) {
			console.log("Publish cancelled");
			return false;
		}

		const order = this.getPublishOrder();
		console.log("\n📋 Publish order:", order.join(" → "));

		for (const packageName of order) {
			const pkg = this.packages.get(packageName)!;
			try {
				await this.publishPackage(pkg);
				pkg.published = true;
			} catch (error) {
				console.error(`\n❌ Failed to publish ${packageName}:`, error);
				break;
			}
		}

		const successful = Array.from(this.packages.values()).filter(p => p.published).map(p => p.name);
		const failed = Array.from(this.packages.values()).filter(p => !p.published).map(p => p.name);

		console.log("\n📊 Publish Summary:");
		if (successful.length > 0) {
			console.log("✅ Successfully published:", successful.join(", "));
		}
		if (failed.length > 0) {
			console.log("❌ Failed to publish:", failed.join(", "));
			return false;
		}

		return true;
	}
}