# كليك + ترند

موقع عربي RTL لاستوديو تسويق رقمي، مبني باستخدام React وVite وTypeScript وTailwind CSS. يحتوي على صفحات عامة ومعرض أعمال ديناميكي ونموذج استقبال العملاء ومساحة فريق مرتبطة بـSupabase.

## التشغيل المحلي

1. ثبّت Node.js 20 أو أحدث.
2. شغّل `npm install`.
3. انسخ `.env.example` إلى `.env.local` وأدخل رابط مشروع Supabase و`anon` key.
4. طبّق مخطط قاعدة البيانات الموضح أدناه.
5. شغّل `npm run dev` وافتح الرابط المحلي الذي يعرضه Vite.

يعمل الموقع من دون Supabase للمعاينة البصرية. إرسال النماذج والدخول والمحادثات ولوحة الموظفين تحتاج إعداد Supabase صالحاً.

## إعداد Supabase

1. أنشئ مشروعاً جديداً في Supabase.
2. من **Project Settings → API** انسخ Project URL و`anon` key إلى `.env.local` بالمتغيرين `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY`.
3. ثبّت Supabase CLI، ثم نفّذ `supabase link --project-ref YOUR_PROJECT_REF` و`supabase db push` من جذر المشروع. أو شغّل `supabase/migrations/202610130001_initial_schema.sql` مرة واحدة في SQL Editor.
4. أنشئ حساب الموظف الأول من **Authentication → Users**. بعد ذلك، في SQL Editor، عيّن دور المدير إلى UUID ذلك الحساب:

   ```sql
   update public.profiles
   set role = 'super_admin', account_type = 'staff'
   where id = 'AUTH_USER_UUID';
   ```

   لا تضع service role key في الواجهة أو في أي ملف يبدأ بـ`VITE_`. نفّذ تعيين الدور من لوحة Supabase بصلاحية المالك.
5. أضف الموظفين من Authentication ثم عيّن `account_type = 'staff'` والدور المناسب لهم من جدول `profiles`. العملاء الذين ينشئون حساباً من الموقع يبقون `account_type = 'client'` ولا يمكنهم منح أنفسهم صلاحية أعلى.
6. أضف بيانات الخدمات والباقات والأعمال الحقيقية من لوحة Supabase أو لوحة الفريق. لن تظهر باقات أو أعمال مختلقة عند خلو قاعدة البيانات.

## الأدوار والبيانات

- `super_admin`: إدارة الفريق والطلبات والمحتوى والباقات.
- `sales`: متابعة العملاء والمحادثات وتحديث مراحل الطلب.
- `content_manager`: إدارة الأعمال والخدمات وملفات المعرض.
- `viewer`: قراءة محدودة للوحة الفريق، من دون الوصول إلى بيانات العملاء أو محادثاتهم.

تُطبق سياسات RLS في PostgreSQL على كل الجداول. نموذج العملاء عام للإضافة فقط، ومحادثات العميل محصورة في غرفه، وملفات الوسائط تحفظ في bucket باسم `portfolio`. المخطط والسياسات في `supabase/migrations/`.

## الأوامر

- `npm run dev` — خادم التطوير.
- `npm run lint` — فحص ESLint.
- `npm run build` — فحص TypeScript وإنشاء نسخة الإنتاج.
- `npm run preview` — معاينة نسخة الإنتاج محلياً.

تحتاج مصادقة Supabase إلى تفعيل مزود البريد الإلكتروني وتحديد عناوين إعادة التوجيه في لوحة المشروع. إعداد SMTP مخصص اختياري للإنتاج.
