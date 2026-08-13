import axios, { AxiosRequestConfig } from 'axios';
import { HttpError } from './HttpError';

// DISCOVERY CONFIG
const HOSTS = process.env.MT5_HOST ? [process.env.MT5_HOST] : ['127.0.0.1', 'host.docker.internal', '172.17.0.1'];
let workingHostIndex = 0;

const getApi = (host: string) => axios.create({
    baseURL: `http://${host}:8890/v1`,
    timeout: 30000, // Increased timeout for slow MT5 responses
});

let api = getApi(HOSTS[workingHostIndex]);

export async function apiRequest<T>(config: AxiosRequestConfig): Promise<T> {
    try {
        const response = await api.request<T>(config);
        return response.data;
    } catch (err: any) {
        const isNetworkError = axios.isAxiosError(err) &&
            (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND' || err.code === 'ETIMEDOUT' || err.code === 'ECONNABORTED');

        if (isNetworkError) {
            console.log(`⚠️ Bridge: Host ${HOSTS[workingHostIndex]} failed (${err.code}). Cycling discovery...`);

            // Try each host until one works
            for (let i = 0; i < HOSTS.length; i++) {
                const trialIndex = (workingHostIndex + i + 1) % HOSTS.length;
                const trialHost = HOSTS[trialIndex];

                try {
                    console.log(`🔍 Bridge: Trying discovery on ${trialHost}...`);
                    const trialApi = getApi(trialHost);
                    // Minimal ping to check if EA is there
                    await trialApi.get('/account', { timeout: 5000 });

                    console.log(`✅ Bridge: Discovered working MT5 host at ${trialHost}`);
                    workingHostIndex = trialIndex;
                    api = trialApi;

                    // Retry original request with new host
                    const retryResponse = await api.request<T>(config);
                    return retryResponse.data;
                } catch (e) {
                    continue;
                }
            }
        }

        const status = err.response?.status || 500;
        const data = err.response?.data;
        const msg = (typeof data === 'object' && data?.details) ? data.details : (data || err.message);

        throw new HttpError(status, msg, data);
    }
}
