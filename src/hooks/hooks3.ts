/**
 * hooks3.ts
 * 第三个钩子
 * 
 * 提供第三个钩子功能
 * 
 * @param {number} a - 第一个数字
 * @param {number} b - 第二个数字
 * @returns {number} 两个数字的和
 */
function hooks3(a, b) {
    console.log('第三个钩子:', a, b);
    const result = a + b + 5;
    const hooks2 = hooks2(a, b);
    return result + hooks2;
}

module.exports = hooks3;

console.log(hooks3(1, 2));