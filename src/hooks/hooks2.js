/**
 * hooks2.js
 * 第二个钩子
 * 
 * 提供第二个钩子功能
 * 
 * @param {number} a - 第一个数字
 * @param {number} b - 第二个数字
 * @returns {number} 两个数字的和
 */
function hooks2(a, b) {
    console.log('第二个钩子:', a, b);
    const result = a + b + 4;
    const point = new Point(1, 2, 3);
    let money = calcMoney(100);
    let addTwo = addTwo(1, 2);
    const otherTest = otherTest(1, 2);

    const result2 = result + point.x + point.y + point.z + money + addTwo + otherTest;
    return result2;
}