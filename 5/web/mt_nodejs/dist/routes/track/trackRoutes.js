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
 * /track/prices:
 *   post:
 *     summary: Track symbols
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               symbols:
 *                 type: array
 *                 items:
 *                   type: string
 *                 example: ["EURUSD", "GBPUSD"]
 *     responses:
 *       200:
 *         description: Tracking initiated successfully
 */
router.post('/track/prices', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const body = req.body;
        const result = yield (0, SocketBridgeApi_1.postTrackPrices)(body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}));
/**
 * @swagger
 * /track/ohlc:
 *   post:
 *     summary: Track OHLC data
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               ohlc:
 *                 type: array
 *                 items:
 *                   type: object
 *                   properties:
 *                     time_frame:
 *                       type: string
 *                       example: M1
 *                     symbol:
 *                       type: string
 *                       example: EURUSD
 *                     depth:
 *                       type: integer
 *                       example: 3
 *     responses:
 *       200:
 *         description: Tracking initiated successfully
 */
router.post('/track/ohlc', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const body = req.body;
        const result = yield (0, SocketBridgeApi_1.postTrackOhlc)(body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}));
/**
 * @swagger
 * /track/mbook:
 *   post:
 *     summary: Track market book data
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               symbols:
 *                 type: array
 *                 items:
 *                   type: string
 *                 example: ["EURUSD", "USDJPY"]
 *     responses:
 *       200:
 *         description: Tracking initiated successfully
 */
router.post('/track/mbook', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const body = req.body;
        const result = yield (0, SocketBridgeApi_1.postTrackMbook)(body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}));
/**
 * @swagger
 * /track/orders:
 *   post:
 *     summary: Track order events
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               symbols:
 *                 type: array
 *                 items:
 *                   type: string
 *                 example: ["BTCUSD", "ETHUSD"]
 *     responses:
 *       200:
 *         description: Tracking initiated successfully
 */
router.post('/track/orders', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const body = req.body;
        const result = yield (0, SocketBridgeApi_1.postTrackOrders)(body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}));
exports.default = router;
