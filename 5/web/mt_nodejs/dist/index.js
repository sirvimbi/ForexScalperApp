"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const dataRoute_1 = __importDefault(require("./routes/dataRoute"));
const swagger_ui_express_1 = __importDefault(require("swagger-ui-express"));
const swagger_1 = __importDefault(require("./swagger"));
const HttpError_1 = require("./utils/HttpError");
const app = (0, express_1.default)();
app.use((0, cors_1.default)());
app.use(express_1.default.json());
app.use('/v1', dataRoute_1.default);
app.use('/api-docs', swagger_ui_express_1.default.serve, swagger_ui_express_1.default.setup(swagger_1.default));
app.use((err, req, res, next) => {
    var _a, _b, _c;
    console.error(err);
    if (err instanceof HttpError_1.HttpError) {
        res.status(err.statusCode).json({
            error: {
                message: err.message,
                statusCode: err.statusCode,
                details: (_c = (_b = (_a = err.details) === null || _a === void 0 ? void 0 : _a.details) !== null && _b !== void 0 ? _b : err.details) !== null && _c !== void 0 ? _c : null,
            },
        });
        return;
    }
    res.status(500).json({
        error: {
            message: 'Internal Server Error',
            statusCode: 500,
        },
    });
});
const PORT = process.env.PORT || 8891;
app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});
