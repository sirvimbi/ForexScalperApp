"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.apiRequest = apiRequest;
const axios_1 = __importDefault(require("axios"));
const HttpError_1 = require("./HttpError");
// DISCOVERY CONFIG
const HOSTS = [process.env.MT5_HOST || 'host.docker.internal', '127.0.0.1', '172.17.0.1'];
let workingHostIndex = 0;
const getApi = (host) => axios_1.default.create({
    baseURL: `http://${host}:8890/v1`,
    timeout: 25000,
});
let api = getApi(HOSTS[workingHostIndex]);
function apiRequest(config) {
    return __awaiter(this, void 0, void 0, function* () {
        var _a, _b;
        try {
            const response = yield api.request(config);
            return response.data;
        }
        catch (err) {
            if (axios_1.default.isAxiosError(err) && (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND')) {
                console.log(`⚠️ Bridge: Host ${HOSTS[workingHostIndex]} failed. Cycling discovery...`);
                // Try each host until one works
                for (let i = 0; i < HOSTS.length; i++) {
                    const trialIndex = (workingHostIndex + i + 1) % HOSTS.length;
                    const trialHost = HOSTS[trialIndex];
                    try {
                        const trialApi = getApi(trialHost);
                        // Minimal ping to check if EA is there
                        yield trialApi.get('/account', { timeout: 2000 });
                        console.log(`✅ Bridge: Discovered working MT5 host at ${trialHost}`);
                        workingHostIndex = trialIndex;
                        api = trialApi;
                        return yield apiRequest(config);
                    }
                    catch (e) {
                        continue;
                    }
                }
            }
            const status = ((_a = err.response) === null || _a === void 0 ? void 0 : _a.status) || 500;
            const data = (_b = err.response) === null || _b === void 0 ? void 0 : _b.data;
            const msg = (typeof data === 'object' && (data === null || data === void 0 ? void 0 : data.details)) ? data.details : (data || err.message);
            throw new HttpError_1.HttpError(status, msg, data);
        }
    });
}
