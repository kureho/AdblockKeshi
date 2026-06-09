-- spec rev4 §2 ad_type 追加: ユーザーが選択した広告タイプ
-- 値は workers/src/lib/ad-type.ts の AD_TYPES と一致 (10 値)。
-- NULL は v3.0 build 14 (= 旧 client) からの報告で許容。
ALTER TABLE reports ADD COLUMN ad_type TEXT;
CREATE INDEX idx_reports_ad_type ON reports(ad_type);
