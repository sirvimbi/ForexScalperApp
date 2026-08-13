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
 * /order/list:
 *   get:
 *     summary: Get list of orders
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/order/list', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const orders = yield (0, SocketBridgeApi_1.fetchOrderList)();
        res.json(orders);
    }
    catch (error) {
        next(error);
    }
}));
/**
 * @swagger
 * /order:
 *   post:
 *     summary: Send order
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               symbol:
 *                 type: string
 *                 example: "EURUSD"
 *               volume:
 *                 type: number
 *                 example: 0.1
 *               order_type:
 *                 type: string
 *                 example: "buy"
 *             required:
 *               - order_type
 *     responses:
 *       200:
 *         description: Success
 */
router.post('/order', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const body = req.body;
        console.log("📦 Bridge: Received Order Request:", JSON.stringify(body, null, 2));
        // Sanitize symbol if present
        if (body.symbol) {
            body.symbol = body.symbol.replace(/\//g, '');
        }
        const result = yield (0, SocketBridgeApi_1.postSendOrder)(body);
        console.log("✅ Bridge: EA Response:", JSON.stringify(result, null, 2));
        res.json(result);
    }
    catch (error) {
        console.error("❌ Bridge: Order execution error:", error);
        next(error);
    }
}));
/**
 * @swagger
 * /order/close:
 *   post:
 *     summary: close order
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               ticket:
 *                 type: integer
 *                 example: 5144525742
 *             required:
 *               - ticket
 *     responses:
 *       200:
 *         description: Success
 */
router.post('/order/close', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const body = req.body;
        //validate later
        const result = yield (0, SocketBridgeApi_1.closeSendOrder)(body);
        res.json(result);
    }
    catch (error) {
        next(error);
    }
}));
exports.default = router;
