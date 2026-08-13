import { Router, Request, Response, NextFunction } from 'express';
import { fetchSymbolList, fetchSymbolInfo } from '../../services/SocketBridgeApi';

const router = Router();

/**
 * @swagger
 * /symbol/list:
 *   get:
 *     summary: Get all symbols
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/symbol/list', async (req: Request, res: Response, next: NextFunction) => {
    try {
        const symbols = await fetchSymbolList();
        res.json(symbols);
    } catch (error) {
        next(error);
    }
});

/**
 * @swagger
 * /symbol/info:
 *   get:
 *     summary: Get symbol info
 *     parameters:
 *       - in: query
 *         name: symbol
 *         schema:
 *           type: string
 *         required: true
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/symbol/info', async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { symbol } = req.query;
        const info = await fetchSymbolInfo(symbol as string);
        res.json(info);
    } catch (error) {
        next(error);
    }
});

export default router;
