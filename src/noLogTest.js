/**
 * noLogTest.js
 * 不记录日志测试模块
 * 
 * 提供不记录日志测试功能
 * 
 * @param {number} a - 第一个数字
 * @param {number} b - 第二个数字
 * @returns {number} 两个数字的和
 */
function noLogTest(a, b) {
    console.log('不记录日志测试:', a, b);
    const result = a + b + 6;
    return result;
}

module.exports = noLogTest;

console.log(noLogTest(1, 2));