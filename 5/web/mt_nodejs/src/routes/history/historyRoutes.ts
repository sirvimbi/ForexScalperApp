import { Router, Request, Response, NextFunction } from 'express';
import {fetchOrderHistory, fetchPriceHistory, OrderHistoryParams, PriceHistoryParams} from '../../services/SocketBridgeApi';

const router = Router();

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
router.get('/history/orders', async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { mode, from_date, to_date, count } = req.query;

        const historyParams: OrderHistoryParams & { count?: number } = {
            mode: mode as string,
        };

        const countVal = count ? parseInt(count as string) : 0;

        if (countVal > 0) {
            historyParams.count = countVal;
            delete (historyParams as any).from_date;
            delete (historyParams as any).to_date;
        } else {
            if (from_date) historyParams.from_date = from_date as string;
            if (to_date) historyParams.to_date = to_date as string;
        }

        const history = await fetchOrderHistory(historyParams);
        res.json(history);
    } catch (error) {
        next(error);
    }
});

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
router.get('/history/prices', async (req: Request, res: Response, next: NextFunction) => {
    try {
        let { symbol, time_frame, from_date, to_date, count } = req.query;

        // Sanitize symbol
        let cleanSymbol = (symbol as string)?.replace(/\//g, '');

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
            const tf = (time_frame as string) || 'M1';
            let daysBack = 1;

            if (tf === 'W1') daysBack = 365; // 1 year for weekly trend
            else if (tf === 'D1') daysBack = 180; // 6 months for daily
            else if (tf === 'H4' || tf === 'H1') daysBack = 30; // 1 month for hourly
            else if (tf.includes('M30') || tf.includes('M15')) daysBack = 7; // 1 week
            else daysBack = 2; // 2 days for M1/M5

            const start = new Date(now.getTime() - (daysBack * 24 * 60 * 60 * 1000));
            from_date = start.toISOString().split('.')[0];
            to_date = end.toISOString().split('.')[0];

            console.log(`ℹ️ Bridge: Auto-generating date range for ${cleanSymbol} [${tf}]: ${from_date} to ${to_date}`);
        }

        const historyParams: PriceHistoryParams = {
            symbol: cleanSymbol,
            time_frame: time_frame as string,
        };

        const countVal = count ? parseInt(count as string) : 0;

        if (countVal > 0) {
            historyParams.count = countVal;
            // Strictly exclude dates if count is used
            delete (historyParams as any).from_date;
            delete (historyParams as any).to_date;
        } else {
            if (from_date) historyParams.from_date = from_date as string;
            if (to_date) historyParams.to_date = to_date as string;
        }

        console.log(`🌐 Bridge: Fetching history for ${cleanSymbol} with params:`, JSON.stringify(historyParams));
        const prices = await fetchPriceHistory(historyParams);

        res.json(prices);
    } catch (error) {
        next(error);
    }
});

export default router;