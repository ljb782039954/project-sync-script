/**
 * point.js
 * 点类
 * 
 * 提供点的坐标
 * 
 * @param {number} x - 点的x坐标
 * @param {number} y - 点的y坐标
 * @returns {number} 点的坐标
 */
function Point(x, y, z = 0) {
    this.x = x;
    this.y = y;
    this.z = z;
}

module.exports = Point;

console.log(Point(1, 2, 3));
