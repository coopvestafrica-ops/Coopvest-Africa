/**
 * Coopvest Africa - Referral System Backend API
 * 
 * Main entry point for the Express server with WebSocket support
 * 
 * Security Features:
 * - JWT authentication
 * - IP whitelisting for admin routes
 * - HTTPS enforcement with HSTS
 * - Rate limiting
 * - Security headers
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const http = require('http');
// const connectDB = require('./config/database'); // Removed for Supabase migration
const supabase = require('./config/supabase');
const logger = require('./utils/logger');

// Import services
const websocketService = require('./services/websocketService');

// Import routes
const authRoutes = require('./routes/auth');
const emailVerificationRoutes = require('./routes/emailVerification');
const referralRoutes = require('./routes/referrals');
const ticketRoutes = require('./routes/tickets');
const adminTicketRoutes = require('./routes/adminTickets');
const adminRoutes = require('./routes/admin');
const loanRoutes = require('./routes/loans');
const walletRoutes = require('./routes/wallet');
const userRoutes = require('./routes/user');
const kycRoutes = require('./routes/kyc');
const savingsRoutes = require('./routes/savings');
const rolloverRoutes = require('./routes/rollover');
const investmentsRoutes = require('./routes/investments');
const notificationRoutes = require('./routes/notifications');
const bankAccountRoutes = require('./routes/bankAccounts');
const transactionRoutes = require('./routes/transactions');
const settingsRoutes = require('./routes/settings');
const watchlistRoutes = require('./routes/watchlist');
const analyticsRoutes = require('./routes/analytics');
const adminApiRoutes = require('./routes/adminApi');
const kycAdminRoutes = require('./routes/kycAdmin');
const memberDetailRoutes = require('./routes/memberDetail');
const guarantorRoutes = require('./routes/guarantor');
const announcementRoutes = require('./routes/announcements');
const contributionRoutes = require('./routes/contributions');
const documentRoutes = require('./routes/documents');
const terminationRoutes = require('./routes/termination');
const featuresRoutes = require('./routes/features');

// Import middleware
const errorHandler = require('./middleware/errorHandler');
const { enforceHTTPS, securityHeaders, securityLogger } = require('./middleware/httpsEnforcement');
const { adminIPWhitelist } = require('./middleware/ipWhitelist');
const { sanitizeMiddleware } = require('./middleware/sanitize');

const app = express();
const PORT = process.env.PORT || 8080;

// Create HTTP server
const server = http.createServer(app);

// MongoDB connection removed - project now uses Supabase for all data persistence
logger.info('ℹ️ Using Supabase for data persistence');

// Log Supabase status
if (process.env.SUPABASE_URL) {
  logger.info('✅ Supabase integration active');
}

// Initialize WebSocket server
websocketService.initialize(server);

// ==============================================================================
// TRUST PROXY (Required for proper IP detection behind load balancer/proxy)
// ==============================================================================
app.set('trust proxy', true);

// ==============================================================================
// HTTPS ENFORCEMENT & SECURITY HEADERS
// ==============================================================================
// Only enforce HTTPS in production
if (process.env.NODE_ENV === 'production') {
  app.use(enforceHTTPS);
}
app.use(securityHeaders);
app.use(securityLogger);

// ==============================================================================
// CORS CONFIGURATION
// ==============================================================================
const corsOriginEnv = process.env.CORS_ORIGIN || '';
const allowAllOrigins = corsOriginEnv === '*';
const allowedOrigins = allowAllOrigins 
  ? [] 
  : corsOriginEnv
      .split(',')
      .map(origin => origin.trim())
      .filter(origin => origin.length > 0);

app.use(cors({
  origin: function (origin, callback) {
    // Allow requests with no origin (mobile apps, curl, Postman, etc.)
    // This is ESSENTIAL for Flutter/mobile apps which don't send Origin header
    if (!origin) return callback(null, true);
    
    // Allow all origins if CORS_ORIGIN is set to "*"
    if (allowAllOrigins) return callback(null, true);
    
    // Allow localhost for development
    if (process.env.NODE_ENV !== 'production') {
      if (origin.includes('localhost') || origin.includes('127.0.0.1')) {
        return callback(null, true);
      }
    }
    
    // Check if origin is in allowed list
    if (allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    
    // Log rejected origins in production
    if (process.env.NODE_ENV === 'production') {
      logger.warn(`CORS rejected origin: ${origin}`);
    }
    
    return callback(new Error('Not allowed by CORS'));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-ID', 'X-Requested-With', 'Accept'],
  credentials: true,
  maxAge: 86400 // 24 hours
}));

// ==============================================================================
// RATE LIMITING
// ==============================================================================
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000,
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
  message: {
    success: false,
    error: 'Too many requests, please try again later.',
    retryAfter: Math.ceil((parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 900000) / 1000)
  },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    // Use X-Forwarded-For for proxied requests
    return req.headers['x-forwarded-for'] || req.ip || req.connection.remoteAddress;
  }
});
app.use('/api/', limiter);

// Stricter rate limiting for auth endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // 10 requests per window
  message: {
    success: false,
    error: 'Too many authentication attempts, please try again later.'
  },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    return req.body?.email || req.ip || req.connection.remoteAddress;
  }
});

// ==============================================================================
// BODY PARSER
// ==============================================================================
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// NoSQL injection protection removed - project now uses SQL (Supabase)
// app.use(sanitizeMiddleware);

// ==============================================================================
// LOGGING
// ==============================================================================
if (process.env.NODE_ENV === 'development') {
  app.use(morgan('dev'));
} else {
  // Use morgan with winston in production
  app.use(morgan('combined', {
    stream: { write: message => logger.info(message.trim()) }
  }));
}

// ==============================================================================
// HEALTH CHECK (No IP restriction)
// ==============================================================================
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Coopvest Africa API',
    version: '1.0.0'
  });
});

app.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'Coopvest API is running',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development'
  });
});

// WebSocket stats endpoint (requires authentication)
const { authenticate } = require('./middleware/auth');
app.get('/ws/stats', authenticate, (req, res) => {
  const stats = websocketService.getStats();
  res.json({
    success: true,
    websocket: stats
  });
});

// ==============================================================================
// SYSTEM STATUS (maintenance mode + minimum app version enforcement)
// ==============================================================================
const { enforceSystemStatus } = require('./middleware/systemStatus');
app.use(enforceSystemStatus);

const { requireFeatureFlag, seedRequiredFlags } = require('./middleware/featureFlags');
// Seed the 10 required feature flags (idempotent).
seedRequiredFlags();

// ==============================================================================
// API ROUTES - MEMBER ENDPOINTS (No IP whitelist)
// ==============================================================================
app.use('/api/v1/auth', authLimiter, authRoutes);
app.use('/api/v1/auth', emailVerificationRoutes);
app.use('/api/v1/referrals', requireFeatureFlag('referralSystem'), referralRoutes);
app.use('/api/v1/tickets', ticketRoutes);
app.use('/api/v1/loans', requireFeatureFlag('loanModule'), loanRoutes);
app.use('/api/v1/wallet', walletRoutes);
app.use('/api/v1/user', userRoutes);
app.use('/api/v1/kyc', kycRoutes);
app.use('/api/v1/savings', requireFeatureFlag('savingsModule'), savingsRoutes);
app.use('/api/v1/rollover', rolloverRoutes);
app.use('/api/v1/investments', requireFeatureFlag('investmentModule'), investmentsRoutes);
app.use('/api/v1/notifications', requireFeatureFlag('notifications'), notificationRoutes);
app.use('/api/v1/bank-accounts', bankAccountRoutes);
app.use('/api/v1/transactions', transactionRoutes);
app.use('/api/v1/settings', settingsRoutes);
app.use('/api/v1/watchlist', watchlistRoutes);
app.use('/api/v1/analytics', analyticsRoutes);
app.use('/api/v1/guarantor', guarantorRoutes);
app.use('/api/v1/announcements', announcementRoutes);
app.use('/api/v1/contributions', contributionRoutes);
app.use('/api/v1/documents', documentRoutes);
app.use('/api/v1/termination', terminationRoutes);

// ==============================================================================
// FLUTTER APP COMPATIBILITY — /api/<path> mirrors /api/v1/<path>
// The Flutter Dio client uses baseUrl=/api, so all requests hit /api/<path>.
// Each route set is mounted at BOTH prefixes to avoid 404s from either client.
// This is intentional duplication to maintain backward compatibility.
// ==============================================================================
app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/auth', emailVerificationRoutes);
app.use('/api/referrals', requireFeatureFlag('referralSystem'), referralRoutes);
app.use('/api/tickets', ticketRoutes);
app.use('/api/loans', requireFeatureFlag('loanModule'), loanRoutes);
app.use('/api/wallet', walletRoutes);
app.use('/api/user', userRoutes);
app.use('/api/kyc', kycRoutes);
app.use('/api/savings', requireFeatureFlag('savingsModule'), savingsRoutes);
app.use('/api/rollover', rolloverRoutes);
app.use('/api/investments', requireFeatureFlag('investmentModule'), investmentsRoutes);
app.use('/api/notifications', requireFeatureFlag('notifications'), notificationRoutes);
app.use('/api/bank-accounts', bankAccountRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/watchlist', watchlistRoutes);
app.use('/api/analytics', analyticsRoutes);
app.use('/api/guarantor', guarantorRoutes);
app.use('/api/announcements', announcementRoutes);
app.use('/api/contributions', contributionRoutes);
app.use('/api/documents', documentRoutes);
app.use('/api/termination', terminationRoutes);
app.use('/api', featuresRoutes);
app.use('/api/mobile-features', featuresRoutes);
// Root-level alias in case Dio resolves absolute paths from host root
app.use('/guarantor', guarantorRoutes);

// KYC aliases (Flutter calls /auth/kyc/submit and /auth/kyc/status)
app.post('/api/v1/auth/kyc/submit', (req, res, next) => {
  req.url = '/submit';
  kycRoutes(req, res, next);
});
app.get('/api/v1/auth/kyc/status', (req, res, next) => {
  req.url = '/status';
  kycRoutes(req, res, next);
});
app.post('/api/auth/kyc/submit', (req, res, next) => {
  req.url = '/submit';
  kycRoutes(req, res, next);
});
app.get('/api/auth/kyc/status', (req, res, next) => {
  req.url = '/status';
  kycRoutes(req, res, next);
});

// ==============================================================================
// API ROUTES - ADMIN ENDPOINTS (With IP whitelist)
// ==============================================================================
// Cross-backend service-token endpoints used by the Admin Dashboard API
// server. Authentication is via a shared secret (X-Service-Token) rather than
// IP whitelisting, so the admin backend can be deployed anywhere.
app.use('/api/v2/admin', adminApiRoutes);
app.use('/api/v2/admin/kyc', kycAdminRoutes);
app.use('/api/v2/admin/members', memberDetailRoutes);

// Also mount admin API at /api/ for backwards compatibility with frontend
app.use('/api', adminApiRoutes);
app.use('/api/kyc', kycAdminRoutes);

// In-app admin console endpoints (member JWT + IP whitelist)
app.use('/api/v1/admin', adminIPWhitelist, adminRoutes);
app.use('/api/v1/admin-tickets', adminIPWhitelist, adminTicketRoutes);

// ==============================================================================
// 404 HANDLER
// ==============================================================================
app.use((req, res, next) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found',
    path: req.path
  });
});

// ==============================================================================
// ERROR HANDLER
// ==============================================================================
app.use(errorHandler);

// ==============================================================================
// START SERVER
// ==============================================================================
// Start background workers.
const scheduledNotificationsWorker = require('./workers/scheduledNotificationsWorker');
scheduledNotificationsWorker.start();

const rolloverDeadlineWorker = require('./workers/rolloverDeadlineWorker');
rolloverDeadlineWorker.start();

// Loan Recovery Worker — enforces 3-stage default/penalty process (Loan Policy §4.1)
const loanRecoveryWorker = require('./workers/loanRecoveryWorker');
loanRecoveryWorker.start();

server.listen(PORT, '0.0.0.0', () => {
  logger.info(`🚀 Coopvest Referral API running on port ${PORT}`);
  logger.info(`🌐 WebSocket endpoint: ws://localhost:${PORT}/ws`);
  logger.info(`💚 Health check: http://localhost:${PORT}/health`);
  logger.info(`📊 WebSocket stats: http://localhost:${PORT}/ws/stats`);
  logger.info(`📦 Environment: ${process.env.NODE_ENV || 'development'}`);
  logger.info(`🔒 HTTPS Enforced: ${process.env.NODE_ENV === 'production'}`);
  logger.info(`🛡️ IP Whitelisting: ${process.env.ADMIN_IP_WHITELIST ? 'Enabled' : 'Disabled'}`);
});

// ==============================================================================
// GRACEFUL SHUTDOWN
// ==============================================================================

// Handle unhandled promise rejections
process.on('unhandledRejection', (err) => {
  logger.error('Unhandled Rejection:', err);
  websocketService.shutdown();
  server.close(() => {
    logger.info('Process terminated due to unhandled rejection');
    process.exit(1);
  });
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception:', err);
  process.exit(1);
});

// SIGTERM and SIGINT handlers
const shutdownHandler = (signal) => {
  logger.info(`${signal} received. Shutting down gracefully...`);
  
  // Stop accepting new connections
  server.close(() => {
    logger.info('HTTP server closed');
  });
  
  // Shutdown WebSocket
  websocketService.shutdown();
  
  // Flush logs
  logger.shutdown(() => {
    logger.info('Logger shutdown complete');
    process.exit(0);
  });
  
  // Force exit after 30 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
};

process.on('SIGTERM', () => shutdownHandler('SIGTERM'));
process.on('SIGINT', () => shutdownHandler('SIGINT'));

// ==============================================================================
// UNHANDLED ROUTE WARNING (Development)
// ==============================================================================
if (process.env.NODE_ENV !== 'production') {
  app._router.stack.forEach((layer) => {
    if (layer.route) {
      const methods = Object.keys(layer.route.methods).join(', ').toUpperCase();
      logger.debug(`Route: ${methods} ${layer.route.path}`);
    }
  });
}

module.exports = app;
