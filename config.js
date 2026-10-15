// Supabase 專案：daruma（英檢表都以 gept_ 開頭，與 daruma 原有資料分開）
// 這兩個值是「公開」金鑰，放在 GitHub 沒問題，真正的權限由資料庫的安全規則控制。
// 絕對不要把 service_role 金鑰貼進任何檔案。
window.APP_CONFIG = {
  SUPABASE_URL: "https://eztljbklzxtygicsarhw.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_5QjLNGYhO7d-IMofH3DihA_E8g8e15F",
  QUESTIONS_PER_QUIZ: 30
};
