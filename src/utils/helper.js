// helper.js
// 工具函数库

/**
 * 计算两个数字的和
 * @param {number} a - 第一个数字
 * @param {number} b - 第二个数字
 * @returns {number} 两个数字的和
 */
function calculateSum(a, b) {
    if (typeof a !== 'number' || typeof b !== 'number') {
        throw new Error('参数必须是数字');
    }
    return a + b;
}

/**
 * 格式化消息字符串
 * 在消息前后添加装饰符号
 * @param {string} message - 要格式化的消息
 * @returns {string} 格式化后的消息
 */
function formatMessage(message) {
    if (typeof message !== 'string') {
        throw new Error('参数必须是字符串');
    }
    return `========== ${message} ==========`;
}

/**
 * 验证邮箱地址格式
 * @param {string} email - 要验证的邮箱地址
 * @returns {boolean} 如果格式正确返回 true，否则返回 false
 */
function validateEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

module.exports = {
    calculateSum,
    formatMessage,
    validateEmail
};

