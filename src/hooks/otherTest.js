/**
 * otherTest.js
 * 其他测试模块
 * 
 * 提供其他测试功能
 * 
 * @param {number} a - 第一个数字
 * @param {number} b - 第二个数字
 * @returns {number} 两个数字的和
 */
function otherTest(a, b) {
    console.log('其他测试:', a, b);
    const result = a + b + 3;
    const point = new Point(1, 2, 3);
    return result;
}

module.exports = otherTest;

console.log(otherTest(1, 2));
