DROP DATABASE IF EXISTS MiniSocialNetwork;
CREATE DATABASE MiniSocialNetwork;
USE MiniSocialNetwork;

-- PHẦN 1: TẠO CẤU TRÚC BẢNG (DDL) 

CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) 
) ENGINE=InnoDB;

CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    post_id INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    UNIQUE (user_id, post_id) 
) ENGINE=InnoDB;

CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    friend_id INT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    deleted_content TEXT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- F07: Xem bài viết theo từ khóa (Full-Text Search)
ALTER TABLE posts ADD FULLTEXT INDEX idx_ft_content (content);

-- F06: View Xem thông tin người dùng
CREATE OR REPLACE VIEW view_user_profiles AS
SELECT user_id, username, email, created_at FROM users;

-- =========================================================================
-- PHẦN 2: TRIGGERS THEO ĐÚNG YÊU CẦU GIẢNG VIÊN
-- =========================================================================
DELIMITER //

-- [CẬP NHẬT THEO FEEDBACK] Trigger kiểm soát kết bạn (Chặn trùng lặp, chặn tự kết bạn)
CREATE TRIGGER tg_before_friend_insert
BEFORE INSERT ON friends
FOR EACH ROW
BEGIN
    DECLARE v_count INT;

    -- 1. Chặn tự kết bạn với chính mình
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Không thể tự kết bạn với chính mình!';
    END IF;

    -- 2. Chặn gửi trùng lặp đảo chiều (A -> B hoặc B -> A đã tồn tại)
    SELECT COUNT(*) INTO v_count 
    FROM friends 
    WHERE (user_id = NEW.user_id AND friend_id = NEW.friend_id)
       OR (user_id = NEW.friend_id AND friend_id = NEW.user_id);
       
    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Lời mời kết bạn giữa 2 người này đã tồn tại!';
    END IF;
END //

CREATE TRIGGER trg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id;
END //

CREATE TRIGGER trg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count - 1 WHERE post_id = OLD.post_id;
END //

CREATE TRIGGER trg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count + 1 WHERE post_id = NEW.post_id;
END //

CREATE TRIGGER trg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count - 1 WHERE post_id = OLD.post_id;
END //

CREATE TRIGGER trg_before_post_delete
BEFORE DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, user_id, deleted_content)
    VALUES (OLD.post_id, OLD.user_id, OLD.content);
END //

DELIMITER ;

-- =========================================================================
-- PHẦN 3: STORED PROCEDURES ĐÃ BỔ SUNG ĐẦY ĐỦ LOGIC NGHIỆP VỤ
-- =========================================================================
DELIMITER //

-- [CẬP NHẬT THEO FEEDBACK] F01: Đăng ký thành viên có bẫy lỗi
CREATE PROCEDURE sp_register_user(
    IN p_username VARCHAR(50), 
    IN p_password VARCHAR(255), 
    IN p_email VARCHAR(100),
    OUT p_message VARCHAR(100)
)
BEGIN
    -- Kiểm tra trùng lặp
    IF EXISTS (SELECT 1 FROM users WHERE username = p_username) THEN
        SET p_message = 'Thất bại: Tên đăng nhập đã tồn tại!';
    ELSEIF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
        SET p_message = 'Thất bại: Email đã được sử dụng!';
    ELSE
        INSERT INTO users (username, password, email) VALUES (p_username, p_password, p_email);
        SET p_message = 'Đăng ký thành công!';
    END IF;
END //


-- [CẬP NHẬT THEO FEEDBACK] F02: Đăng bài viết có bẫy lỗi rỗng và kiểm tra User
CREATE PROCEDURE sp_create_post(
    IN p_user_id INT, 
    IN p_content TEXT,
    OUT p_message VARCHAR(100)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        SET p_message = 'Thất bại: Người dùng không tồn tại!';
    ELSEIF TRIM(p_content) = '' OR p_content IS NULL THEN
        SET p_message = 'Thất bại: Nội dung bài viết không được rỗng!';
    ELSE
        INSERT INTO posts (user_id, content) VALUES (p_user_id, p_content);
        SET p_message = 'Đăng bài thành công!';
    END IF;
END //


-- F05: Chấp nhận kết bạn
CREATE PROCEDURE sp_accept_friend(IN p_friendship_id INT)
BEGIN
    UPDATE friends SET status = 'accepted' WHERE friendship_id = p_friendship_id AND status = 'pending';
END //


-- F08: Báo cáo hoạt động của User
CREATE PROCEDURE sp_user_activity_report(IN p_user_id INT)
BEGIN
    SELECT 
        u.username,
        COUNT(DISTINCT p.post_id) AS total_posts,
        IFNULL(SUM(p.like_count), 0) AS total_likes_received,
        IFNULL(SUM(p.comment_count), 0) AS total_comments_received
    FROM users u
    LEFT JOIN posts p ON u.user_id = p.user_id
    WHERE u.user_id = p_user_id
    GROUP BY u.user_id;
END //


-- [CẬP NHẬT THEO FEEDBACK] F11: Đổi đúng tên sp_delete_user và xử lý Transaction chuẩn
CREATE PROCEDURE sp_delete_user(
    IN p_user_id INT,
    OUT p_message VARCHAR(255)
)
proc_label: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'Lỗi hệ thống: Quá trình xóa thất bại, đã hoàn nguyên dữ liệu!';
    END;

    -- Kiểm tra User có tồn tại không
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id) THEN
        SET p_message = 'Thất bại: Người dùng không tồn tại!';
        LEAVE proc_label;
    END IF;

    -- Bắt đầu giao dịch xóa toàn vẹn
    START TRANSACTION;
    
    -- Bước 1: Xóa tương tác của user
    DELETE FROM likes WHERE user_id = p_user_id;
    DELETE FROM comments WHERE user_id = p_user_id;
    
    -- Bước 2: Xóa quan hệ bạn bè
    DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;
    
    -- Bước 3: Xóa bài viết của user (Các comment/like trên bài này sẽ bị xóa theo nhờ CASCADE)
    DELETE FROM posts WHERE user_id = p_user_id;
    
    -- Bước 4: Xóa tài khoản gốc
    DELETE FROM users WHERE user_id = p_user_id;

    COMMIT;
    SET p_message = 'Thành công: Đã xóa tài khoản và mọi dữ liệu liên quan!';
END //

DELIMITER ;