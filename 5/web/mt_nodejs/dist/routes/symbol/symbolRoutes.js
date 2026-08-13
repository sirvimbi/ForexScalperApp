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
 * /symbol/list:
 *   get:
 *     summary: Get all symbols
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/symbol/list', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const symbols = yield (0, SocketBridgeApi_1.fetchSymbolList)();
        res.json(symbols);
    }
    catch (error) {
        next(error);
    }
}));
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
router.get('/symbol/info', (req, res, next) => __awaiter(void 0, void 0, void 0, function* () {
    try {
        const { symbol } = req.query;
        const info = yield (0, SocketBridgeApi_1.fetchSymbolInfo)(symbol);
        res.json(info);
    }
    catch (error) {
        next(error);
    }
}));
exports.default = router;
