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
const SocketBridgeApi_1 = require("../services/SocketBridgeApi");
const router = (0, express_1.Router)();
/**
 * @swagger
 * /status:
 *   get:
 *     summary: Get bridge status
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/status', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const account = yield (0, SocketBridgeApi_1.fetchAccount)();
        res.json({
            status: "online",
            connected: true,
            terminal: "MetaTrader 5",
            account: account
        });
    }
    catch (error) {
        res.status(503).json({
            status: "offline",
            connected: false,
            message: "MT5 EA not reachable on port 8890",
            error: error instanceof Error ? error.message : String(error)
        });
    }
}));
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
router.get('/quote', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const { symbol } = req.query;
        const quote = yield (0, SocketBridgeApi_1.getQuote)(symbol);
        res.json(quote);
    }
    catch (error) {
        next(error);
    }
}));
exports.default = router;
