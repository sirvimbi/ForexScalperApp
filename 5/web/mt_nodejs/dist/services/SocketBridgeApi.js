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
exports.getQuote = exports.postTrackOrders = exports.postTrackMbook = exports.postTrackOhlc = exports.postTrackPrices = exports.fetchPriceHistory = exports.fetchOrderHistory = exports.fetchSymbolInfo = exports.fetchSymbolList = exports.fetchAccount = exports.closeSendOrder = exports.postSendOrder = exports.fetchOrderList = void 0;
const apiClient_1 = require("../utils/apiClient");
// order
const fetchOrderList = () => __awaiter(void 0, void 0, void 0, function* () {
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: '/order/list',
    });
});
exports.fetchOrderList = fetchOrderList;
const postSendOrder = (body) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Posting send order...");
    return (0, apiClient_1.apiRequest)({
        method: 'POST',
        url: '/order',
        data: body
    });
});
exports.postSendOrder = postSendOrder;
const closeSendOrder = (body) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Posting close order...");
    return (0, apiClient_1.apiRequest)({
        method: 'POST',
        url: '/order/close',
        data: body
    });
});
exports.closeSendOrder = closeSendOrder;
// account
const fetchAccount = () => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Fetching account information...");
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: '/account',
    });
});
exports.fetchAccount = fetchAccount;
// symbols
const fetchSymbolList = () => __awaiter(void 0, void 0, void 0, function* () {
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: '/symbol/list',
    });
});
exports.fetchSymbolList = fetchSymbolList;
const fetchSymbolInfo = (symbol) => __awaiter(void 0, void 0, void 0, function* () {
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: `/symbol/info?symbol=${encodeURIComponent(symbol)}`,
    });
});
exports.fetchSymbolInfo = fetchSymbolInfo;
const fetchOrderHistory = (params) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Fetching order history...");
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: '/history/orders',
        params
    });
});
exports.fetchOrderHistory = fetchOrderHistory;
const fetchPriceHistory = (params) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Fetching price history...");
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: '/history/prices',
        params
    });
});
exports.fetchPriceHistory = fetchPriceHistory;
const postTrackPrices = (body) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Posting track prices...");
    return (0, apiClient_1.apiRequest)({
        method: 'POST',
        url: '/track/prices',
        data: body
    });
});
exports.postTrackPrices = postTrackPrices;
const postTrackOhlc = (body) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Posting track ohlc...");
    return (0, apiClient_1.apiRequest)({
        method: 'POST',
        url: '/track/ohlc',
        data: body
    });
});
exports.postTrackOhlc = postTrackOhlc;
const postTrackMbook = (body) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Posting track mbook...");
    return (0, apiClient_1.apiRequest)({
        method: 'POST',
        url: '/track/mbook',
        data: body
    });
});
exports.postTrackMbook = postTrackMbook;
const postTrackOrders = (body) => __awaiter(void 0, void 0, void 0, function* () {
    console.log("Posting track order events...");
    return (0, apiClient_1.apiRequest)({
        method: 'POST',
        url: '/track/orders',
        data: body
    });
});
exports.postTrackOrders = postTrackOrders;
const getQuote = (symbol) => __awaiter(void 0, void 0, void 0, function* () {
    console.log(`Fetching quote for symbol: ${symbol}`);
    return (0, apiClient_1.apiRequest)({
        method: 'GET',
        url: `/quote?symbol=${encodeURIComponent(symbol)}`,
    });
});
exports.getQuote = getQuote;
