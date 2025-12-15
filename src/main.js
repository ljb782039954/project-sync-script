// main.js
// 主程序入口文件

const helper = require('./utils/helper');
const config = require('../config/settings.json');

/**
 * 应用程序主函数
 * 这是程序的入口点，负责初始化应用程序
 */
function main() {
    console.log('应用程序启动中...');
    
    // 读取配置信息
    console.log('当前环境:', config.environment);
    console.log('应用名称:', config.appName);
    
    // 使用工具函数
    const result = helper.calculateSum(10, 20);
    console.log('计算结果:', result);
    
    // 格式化输出
    const formatted = helper.formatMessage('欢迎使用本应用程序');
    console.log(formatted);
    
    console.log('应用程序运行完成');
}

// 导出主函数供其他模块使用
module.exports = { main };

// 执行主函数
main();

