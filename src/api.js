// api.js
// API 接口模块

/**
 * 获取用户信息
 * @param {number} userId - 用户ID
 * @returns {Promise<Object>} 用户信息对象
 */
async function getUserInfo(userId) {
    // 模拟 API 调用
    return new Promise((resolve) => {
        setTimeout(() => {
            resolve({
                id: userId,
                name: '测试用户',
                email: 'test@example.com'
            });
        }, 100);
    });
}

/**
 * 更新用户信息
 * @param {number} userId - 用户ID
 * @param {Object} userData - 用户数据
 * @returns {Promise<boolean>} 更新是否成功
 */
async function updateUserInfo(userId, userData) {
    // 模拟 API 调用
    return new Promise((resolve) => {
        setTimeout(() => {
            console.log(`更新用户 ${userId} 的信息:`, userData);
            resolve(true);
        }, 100);
    });
}

module.exports = {
    getUserInfo,
    updateUserInfo
};

