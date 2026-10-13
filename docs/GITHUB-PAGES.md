# GitHub Pages

الواجهة ملفات ثابتة؛ الحسابات والعمليات والمرفقات تبقى في Supabase.

1. ارفع نسخة المصدر المنقحة إلى مستودع GitHub، والفرع main.
2. Settings → Pages → Build and deployment → Source: GitHub Actions.
3. شغّل Deploy GitHub Pages من Actions أو ادفع تعديلًا إلى main.
4. سير العمل يقرأ base_path من Pages ويضبط المسارات تلقائيًا، سواء كان موقع حساب أو موقع مشروع داخل مجلد.
5. أنشئ الحسابين من Supabase Auth مع Auto Confirm User كما في DEPLOYMENT.md، وعطّل التسجيل الذاتي في إعدادات Supabase المستضافة.

لا يتطلب الدخول الحالي SMTP أو روابط تأكيد. المستودع: https://github.com/saleh-data/sheep-app . فعّل Pages من إعدادات المستودع باستخدام GitHub Actions.

قبل نشر مصدر عام، استخدم نسخة منقحة من رسائل البريد الشخصية في migrations/docs/tests، ولا ترفع أي مفاتيح سرية أو ملفات بيئة محلية. المفتاح publishable الموجود في الواجهة عام عمدًا؛ حماية البيانات عبر RLS وعضوية الشريكين. ملف `_headers` يخص Cloudflare ولا يطبّقه GitHub Pages.
