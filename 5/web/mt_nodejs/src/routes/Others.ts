import { Router, Request, Response, NextFunction } from 'express';
import {fetchPriceHistory, getQuote, fetchAccount} from '../services/SocketBridgeApi';

const router = Router();

/**
 * @swagger
 * /status:
 *   get:
 *     summary: Get bridge status
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/status', async (req: Request, res: Response, next: NextFunction) => {
    try {
        const account = await fetchAccount();
        res.json({
            status: "online",
            connected: true,
            terminal: "MetaTrader 5",
            account: account
        });
    } catch (error) {
        res.status(503).json({
            status: "offline",
            connected: false,
            message: "MT5 EA not reachable on port 8890",
            error: error instanceof Error ? error.message : String(error)
        });
    }
});

/**
 * @swagger
 * /quote:
 *   get:
 *     summary: Get quote info
 *     parameters:
 *       - in: query
 *         name: symbol
 *         schema:
 *           type: string
 *         required: true
 *         description: Symbol to get quote for
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/quote', async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { symbol } = req.query;

        const quote = await getQuote(symbol as string);

        res.json(quote);
    } catch (error) {
        next(error);
    }
});


export default router;
