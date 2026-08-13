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
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const SocketBridgeApi_1 = require("../../services/SocketBridgeApi");
const router = (0, express_1.Router)();
/**
 * @swagger
 * /history/orders:
 *   get:
 *     summary: Get order history
 *     parameters:
 *       - in: query
 *         name: mode
 *         schema:
 *           type: string
 *           enum: [positions, orders, deals]
 *         required: false
 *         description: Filter by type (positions, orders, or deals)
 *       - in: query
 *         name: from_date
 *         schema:
 *           type: string
 *           format: date
 *         required: false
 *         description: Start date in YYYY-MM-DD format
 *       - in: query
 *         name: to_date
 *         schema:
 *           type: string
 *           format: date
 *         required: false
 *         description: End date in YYYY-MM-DD format
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/history/orders', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const { mode, from_date, to_date, count } = req.query;
        const historyParams = {
            mode: mode,
        };
        const countVal = count ? parseInt(count) : 0;
        if (countVal > 0) {
            historyParams.count = countVal;
            delete historyParams.from_date;
            delete historyParams.to_date;
        }
        else {
            if (from_date)
                historyParams.from_date = from_date;
            if (to_date)
                historyParams.to_date = to_date;
        }
        const history = yield (0, SocketBridgeApi_1.fetchOrderHistory)(historyParams);
        res.json(history);
    }
    catch (error) {
        next(error);
    }
}));
/**
 * @swagger
 * /history/prices:
 *   get:
 *     summary: Get price history
 *     parameters:
 *       - in: query
 *         name: symbol
 *         schema:
 *           type: string
 *         required: true
 *         description: Trading symbol (e.g., EURUSD)
 *       - in: query
 *         name: time_frame
 *         schema:
 *           type: string
 *         required: true
 *         description: Timeframe (e.g., M1, H1)
 *       - in: query
 *         name: count
 *         schema:
 *           type: integer
 *         description: Number of candles (if from_date/to_date omitted)
 *       - in: query
 *         name: from_date
 *         schema:
 *           type: string
 *         description: Start date in YYYY-MM-DD HH:MM:SS format
 *       - in: query
 *         name: to_date
 *         schema:
 *           type: string
 *         description: End date in YYYY-MM-DD HH:MM:SS format
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/history/prices', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        let { symbol, time_frame, from_date, to_date, count } = req.query;
        // Sanitize symbol
        let cleanSymbol = symbol === null || symbol === void 0 ? void 0 : symbol.replace(/\//g, '');
        // ELITE SYNC LOGIC: If count is present, ignore date generation and let EA handle "Last X bars"
        // This is 100% reliable across all timeframes (M1 to W1) and timezones.
        if (count && !from_date && !to_date) {
            console.log(`📊 Bridge: Fetching last ${count} bars for ${cleanSymbol} [${time_frame}]`);
        }
        else if (!from_date && !to_date) {
            // Fallback for when neither count nor dates are provided
            const now = new Date();
            const end = new Date(now.getTime());
            // Intelligent lookback based on timeframe
            const tf = time_frame || 'M1';
            let daysBack = 1;
            if (tf === 'W1')
                daysBack = 365; // 1 year for weekly trend
            else if (tf === 'D1')
                daysBack = 180; // 6 months for daily
            else if (tf === 'H4' || tf === 'H1')
                daysBack = 30; // 1 month for hourly
            else if (tf.includes('M30') || tf.includes('M15'))
                daysBack = 7; // 1 week
            else
                daysBack = 2; // 2 days for M1/M5
            const start = new Date(now.getTime() - (daysBack * 24 * 60 * 60 * 1000));
            from_date = start.toISOString().split('.')[0];
            to_date = end.toISOString().split('.')[0];
            console.log(`ℹ️ Bridge: Auto-generating date range for ${cleanSymbol} [${tf}]: ${from_date} to ${to_date}`);
        }
        const historyParams = {
            symbol: cleanSymbol,
            time_frame: time_frame,
        };
        const countVal = count ? parseInt(count) : 0;
        if (countVal > 0) {
            historyParams.count = countVal;
            // Strictly exclude dates if count is used
            delete historyParams.from_date;
            delete historyParams.to_date;
        }
        else {
            if (from_date)
                historyParams.from_date = from_date;
            if (to_date)
                historyParams.to_date = to_date;
        }
        console.log(`🌐 Bridge: Fetching history for ${cleanSymbol} with params:`, JSON.stringify(historyParams));
        const prices = yield (0, SocketBridgeApi_1.fetchPriceHistory)(historyParams);
        res.json(prices);
    }
    catch (error) {
        next(error);
    }
}));
exports.default = router;
