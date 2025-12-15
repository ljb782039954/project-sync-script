// config.js
// 配置管理模块

/**
 * 应用配置
 */
const config = {
    // 应用名称
    appName: '测试应用',
    
    // 环境配置
    environment: process.env.NODE_ENV || 'development',
    
    // API 配置
    api: {
        baseUrl: 'https://api.example.com',
        timeout: 5000
    },
    
    // 日志配置
    logging: {
        level: 'info',
        enableFileLog: true
    }
};

module.exports = config;

