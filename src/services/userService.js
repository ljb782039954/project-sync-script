// userService.js
// 用户服务模块

const api = require('../api');

/**
 * 用户服务类
 */
class UserService {
    /**
     * 根据用户ID获取用户信息
     * @param {number} userId - 用户ID
     * @returns {Promise<Object>} 用户信息
     */
    async getUserById(userId) {
        try {
            const userInfo = await api.getUserInfo(userId);
            return userInfo;
        } catch (error) {
            console.error('获取用户信息失败:', error);
            throw error;
        }
    }

    /**
     * 更新用户信息
     * @param {number} userId - 用户ID
     * @param {Object} userData - 要更新的用户数据
     * @returns {Promise<boolean>} 更新是否成功
     */
    async updateUser(userId, userData) {
        try {
            const result = await api.updateUserInfo(userId, userData);
            return result;
        } catch (error) {
            console.error('更新用户信息失败:', error);
            throw error;
        }
    }
}

module.exports = new UserService();

