-- =========================================================================
-- KHỞI TẠO CƠ SỞ DỮ LIỆU
-- =========================================================================
CREATE DATABASE IF NOT EXISTS MiniSocialNetwork;
USE MiniSocialNetwork;

-- =========================================================================
-- PHẦN 1: TẠO CẤU TRÚC BẢNG (DDL) VÀ RÀNG BUỘC (CONSTRAINTS)
-- =========================================================================

-- 1. Bảng Users
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2. Bảng Posts
CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) -- Không CASCADE tự động theo yêu cầu
) ENGINE=InnoDB;

-- 3. Bảng Comments
CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

-- 4. Bảng Likes
CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    post_id INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    UNIQUE (user_id, post_id) -- Chặn 1 user like 1 bài nhiều lần
) ENGINE=InnoDB;

-- 5. Bảng Friends
CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    friend_id INT,
    status VARCHAR(20) CHECK (status IN ('pending', 'accepted')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (friend_id) REFERENCES users(user_id),
    CHECK (user_id != friend_id), -- Chặn tự kết bạn với chính mình
    -- MySQL 8.0+: Functional Unique Index chặn kết bạn đảo chiều (A->B và B->A)
    UNIQUE INDEX idx_unique_friendship ((LEAST(user_id, friend_id)), (GREATEST(user_id, friend_id)))
) ENGINE=InnoDB;

-- 6. Bảng Post_Logs (Bổ sung cho phần 4.1 - Ghi log xóa bài viết)
CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    deleted_content TEXT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


/* =========================================================================
   [ĐỀ XUẤT CẢI TIẾN CHO CẤU TRÚC BẢNG]
   Giải pháp 1 (Soft Delete cho Users): Thay vì xóa vĩnh viễn (Hard Delete) 
   gây mất mát dữ liệu lịch sử, nên thêm cột `is_deleted BOOLEAN DEFAULT FALSE`.
   Khi người dùng xóa tài khoản, ta chỉ cập nhật cờ này thành TRUE.
   
   Giải pháp 2 (Sharding/Partitioning cho Likes/Comments): Mạng xã hội sinh ra 
   dữ liệu tương tác cực lớn. Bảng likes và comments nên được Partition theo 
   tháng (RANGE PARTITIONING) để cải thiện tốc độ truy vấn và dọn dẹp dữ liệu cũ.
========================================================================= */

-- =========================================================================
-- PHẦN 2: INDEXES VÀ VIEWS (F06, F07)
-- =========================================================================

-- F07: Xem bài viết theo từ khóa (Full-Text Search)
ALTER TABLE posts ADD FULLTEXT INDEX idx_ft_content (content);

-- F06: View Xem thông tin người dùng
CREATE OR REPLACE VIEW view_user_profiles AS
SELECT 
    user_id, 
    username, 
    email, 
    created_at
FROM users;

/* =========================================================================
   [ĐỀ XUẤT CẢI TIẾN CHO TÌM KIẾM & VIEW]
   Giải pháp 1 (Tìm kiếm N-gram): Mặc định Full-Text Search của MySQL phân tách
   từ bằng khoảng trắng, không tốt cho tiếng Việt/Á Đông. Nên khai báo thêm 
   `WITH PARSER ngram` khi tạo FullText Index để tìm kiếm tiếng Việt chính xác hơn.
   
   Giải pháp 2 (External Search Engine): Khi content lên tới hàng triệu dòng, 
   Full-Text của MySQL sẽ gây nghẽn RAM. Nên đồng bộ dữ liệu `posts` sang 
   Elasticsearch qua công cụ Logstash, DB chỉ giữ vai trò lưu trữ bản ghi (Source of truth).
========================================================================= */


-- =========================================================================
-- PHẦN 3: TRIGGERS (F03, 4.1)
-- =========================================================================
DELIMITER //

-- 3.1. Trigger Thích bài viết (Tăng like_count)
CREATE TRIGGER trg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id;
END //

-- 3.2. Trigger Hủy thích bài viết (Giảm like_count)
CREATE TRIGGER trg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count - 1 WHERE post_id = OLD.post_id;
END //

-- 3.3. Trigger Bình luận (Tăng comment_count)
CREATE TRIGGER trg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count + 1 WHERE post_id = NEW.post_id;
END //

-- 3.4. Trigger Xóa Bình luận (Giảm comment_count)
CREATE TRIGGER trg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count - 1 WHERE post_id = OLD.post_id;
END //

-- 3.5. Trigger Ghi log xóa bài viết (Lưu trữ content bị xóa)
CREATE TRIGGER trg_before_post_delete
BEFORE DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, user_id, deleted_content)
    VALUES (OLD.post_id, OLD.user_id, OLD.content);
END //

DELIMITER ;

/* =========================================================================
   [ĐỀ XUẤT CẢI TIẾN CHO TRIGGERS]
   Giải pháp 1 (Xử lý Race Condition bằng Cronjob): Nếu 1 bài viết có ca sĩ nổi tiếng,
   hàng chục nghìn người nhấn Like cùng 1 giây, Trigger sẽ gây ra hiện tượng Row Lock 
   cực đoan trên bảng posts. Thay vào đó, tắt Trigger, sử dụng bảng tạm lưu số lượt 
   like mới và dùng Event Scheduler (Cron) của MySQL gộp nhật like_count mỗi phút 1 lần.
   
   Giải pháp 2 (Bảo vệ giá trị âm): Trong các Trigger DELETE, nên thêm logic kiểm tra:
   `IF (like_count > 0) THEN ...` để ngăn chặn lỗi hệ thống khiến count bị âm (Data Drift).
========================================================================= */


-- =========================================================================
-- PHẦN 4: STORED PROCEDURES & TRANSACTIONS (F01, F02, F05, F08, F09, F10, F11)
-- =========================================================================
DELIMITER //

-- F01: Đăng ký thành viên
CREATE PROCEDURE sp_register_user(
    IN p_username VARCHAR(50), 
    IN p_password VARCHAR(255), 
    IN p_email VARCHAR(100)
)
BEGIN
    -- Trong thực tế, p_password đã được băm (hash) từ tầng Backend (NodeJS/Java)
    INSERT INTO users (username, password, email) 
    VALUES (p_username, p_password, p_email);
END //
/* Đề xuất cải tiến F01:
   1. Bẫy lỗi chủ động bằng `EXISTS`: Trả về OUT p_message = 'Email đã tồn tại' thay vì để MySQL văng lỗi đỏ.
   2. Mã hóa tại DB: Có thể dùng `SHA2(p_password, 256)` thẳng trong lệnh INSERT để bảo vệ mật khẩu nếu backend quên băm. */


-- F02: Đăng bài viết
CREATE PROCEDURE sp_create_post(
    IN p_user_id INT, 
    IN p_content TEXT
)
BEGIN
    INSERT INTO posts (user_id, content) VALUES (p_user_id, p_content);
END //
/* Đề xuất cải tiến F02:
   1. Rate Limiting: Kiểm tra bài đăng cuối cùng của p_user_id có cách đây < 30 giây không, nếu có thì chặn để chống Spam.
   2. Lọc từ khóa thô tục: Tích hợp bảng `banned_words`, dùng hàm REGEXP để kiểm tra p_content trước khi cho phép INSERT. */


-- F05: Chấp nhận kết bạn
CREATE PROCEDURE sp_accept_friend(
    IN p_friendship_id INT
)
BEGIN
    UPDATE friends 
    SET status = 'accepted' 
    WHERE friendship_id = p_friendship_id AND status = 'pending';
END //
/* Đề xuất cải tiến F05:
   1. Bảo mật thao tác: Cần truyền thêm `p_current_user_id` để chứng minh người nhấn "Chấp nhận" chính là `friend_id` (người được mời), tránh việc ai đó gọi lậu API đổi status.
   2. Ghi nhận Notification: Mở Transaction, sau khi Update status thì Insert 1 dòng thông báo "A đã chấp nhận lời mời" vào bảng `notifications`. */


-- F08: Báo cáo hoạt động của User
CREATE PROCEDURE sp_user_activity_report(
    IN p_user_id INT
)
BEGIN
    SELECT 
        u.username,
        COUNT(DISTINCT p.post_id) AS total_posts,
        SUM(p.like_count) AS total_likes_received,
        SUM(p.comment_count) AS total_comments_received
    FROM users u
    LEFT JOIN posts p ON u.user_id = p.user_id
    WHERE u.user_id = p_user_id
    GROUP BY u.user_id;
END //
/* Đề xuất cải tiến F08:
   1. Thay vì dùng SUM liên tục khi gọi báo cáo (nặng máy chủ), tạo một bảng `user_stats` và dùng Trigger/Job để đồng bộ dần (CQRS pattern).
   2. Phân trang & Thời gian: Truyền thêm tham số Date_From, Date_To để báo cáo không bị quét toàn bộ dữ liệu lịch sử. */


-- F09: Gợi ý kết bạn (Mutual Friends) sử dụng CTE
CREATE PROCEDURE sp_suggest_friends(
    IN p_user_id INT
)
BEGIN
    -- Tìm danh sách ID những người đang là bạn bè trực tiếp của p_user_id
    WITH MyFriends AS (
        SELECT friend_id AS fid FROM friends WHERE user_id = p_user_id AND status = 'accepted'
        UNION
        SELECT user_id AS fid FROM friends WHERE friend_id = p_user_id AND status = 'accepted'
    ),
    -- Tìm bạn của những người bạn đó
    FriendsOfFriends AS (
        SELECT f.friend_id AS suggested_id
        FROM friends f
        INNER JOIN MyFriends mf ON f.user_id = mf.fid
        WHERE f.status = 'accepted'
        
        UNION ALL
        
        SELECT f.user_id AS suggested_id
        FROM friends f
        INNER JOIN MyFriends mf ON f.friend_id = mf.fid
        WHERE f.status = 'accepted'
    )
    SELECT u.user_id, u.username, COUNT(fof.suggested_id) AS mutual_count
    FROM FriendsOfFriends fof
    INNER JOIN users u ON fof.suggested_id = u.user_id
    WHERE fof.suggested_id != p_user_id -- Không gợi ý chính mình
      AND fof.suggested_id NOT IN (SELECT fid FROM MyFriends) -- Không gợi ý người đã là bạn
    GROUP BY u.user_id, u.username
    ORDER BY mutual_count DESC
    LIMIT 10;
END //
/* Đề xuất cải tiến F09:
   1. Cache Gợi ý: Gợi ý kết bạn là thuật toán rất nặng (Graph Traversal). Nếu tính Realtime bằng SQL trên triệu user DB sẽ sập. Nên dùng Backend (Cronjob) tính toán trước mỗi đêm và lưu vào bảng `friend_suggestions`.
   2. Dùng Graph Database: Gợi ý bạn bè là thế mạnh cốt lõi của Neo4j. Nên đồng bộ mối quan hệ sang Neo4j thay vì dùng CTE của MySQL để đạt tốc độ mili-giây. */


-- F10: Xóa bài viết an toàn (Transaction)
CREATE PROCEDURE sp_delete_post(
    IN p_post_id INT,
    IN p_user_id INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi hệ thống: Xóa bài viết thất bại, đã hoàn nguyên!';
    END;

    START TRANSACTION;
    -- Kiểm tra quyền sở hữu bài viết (chỉ được xóa bài của mình)
    -- Xóa ở bảng `likes` và `comments` sẽ được tự động xử lý bởi ON DELETE CASCADE
    DELETE FROM posts WHERE post_id = p_post_id AND user_id = p_user_id;
    COMMIT;
END //
/* Đề xuất cải tiến F10:
   1. Archive trước khi xóa: Trước khi xóa, COPY bài viết, comment, like vào bảng _history để lưu trữ phục vụ pháp lý trước khi Commit.
   2. Dọn rác S3: Khi post bị xóa, Procedure có thể lưu một Log vào bảng `pending_image_deletion` để Backend biết mà đi xóa ảnh trên Cloud Storage (S3), tránh rác dung lượng. */


-- F11: Xóa tài khoản (Transaction All-or-Nothing) - Không dùng Cascade
CREATE PROCEDURE sp_delete_user_account(
    IN p_user_id INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi toàn vẹn dữ liệu: Không thể xóa tài khoản, đã khôi phục trạng thái cũ!';
    END;

    START TRANSACTION;
    
    -- Bước 1: Xóa các tương tác của user này
    DELETE FROM likes WHERE user_id = p_user_id;
    DELETE FROM comments WHERE user_id = p_user_id;
    
    -- Bước 2: Xóa các mối quan hệ bạn bè (cả chiều gửi và chiều nhận)
    DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;
    
    -- Bước 3: Xóa bài viết của user này 
    -- LƯU Ý: Vì bảng posts ON DELETE CASCADE với bảng likes, comments. 
    -- Nên khi xóa bài, like và comment của NGƯỜI KHÁC trên bài của user này cũng sẽ bay màu theo (đúng nghiệp vụ MXH).
    DELETE FROM posts WHERE user_id = p_user_id;
    
    -- Bước 4: Xóa tài khoản gốc
    DELETE FROM users WHERE user_id = p_user_id;

    COMMIT;
END //
/* Đề xuất cải tiến F11:
   1. Đưa vào hàng đợi (Queue): Xóa 1 KOL có triệu like bằng 1 Transaction lớn sẽ gây Lock toàn bộ DB. Phương pháp đúng là: Đánh dấu `is_banned = TRUE`, sau đó chia nhỏ (Chunking) xóa 1000 comments/likes mỗi batch chạy ngầm ban đêm.
   2. Chặn tự xóa: Cần thêm logic kiểm tra p_user_id có đang vướng khiếu nại (Report) hoặc chưa thanh toán nợ tín dụng ảo không. Nếu có thì `ROLLBACK` và chặn việc xóa tài khoản trốn trách nhiệm. */

DELIMITER ;