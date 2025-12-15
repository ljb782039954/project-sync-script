/**
 * addTwoService.js
 * 加法服务模块
 * 
 * 提供两个数字的加法运算
 * 
 * @param {number} a - 第一个数字
 * @param {number} b - 第二个数字
 * @returns {number} 两个数字的和
 */
function addTwo(a, b) {
    console.log('加法运算:', a, b);
    const result = a + b + 2;

    return result;
}

module.exports = addTwo;

console.log(addTwo(1, 2));

