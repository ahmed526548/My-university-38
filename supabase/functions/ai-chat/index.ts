// Supabase Edge Function: ai-chat
// Required secrets: AI_API_URL, AI_API_KEY, AI_MODEL.
// Keep every provider credential server-side. Deploy with JWT verification enabled.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigin = "https://ahmed526548.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ error: "Method not allowed." }, 405);

  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return respond({ error: "Origin not allowed." }, 403);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return respond({ error: "سجّل الدخول لاستخدام المساعد." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const aiUrl = Deno.env.get("AI_API_URL");
  const aiKey = Deno.env.get("AI_API_KEY");
  const aiModel = Deno.env.get("AI_MODEL");
  if (!supabaseUrl || !anonKey || !aiUrl || !aiKey || !aiModel) {
    return respond({ error: "خدمة المساعد لم يتم إعدادها بعد." }, 503);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return respond({ error: "انتهت جلسة الدخول. سجّل الدخول مرة أخرى." }, 401);

  let body: { messages?: Array<{ role?: string; content?: string }> };
  try {
    const raw = await req.text();
    if (raw.length > 24000) return respond({ error: "حجم المحادثة أكبر من المسموح." }, 413);
    body = JSON.parse(raw);
  } catch {
    return respond({ error: "صيغة الطلب غير صحيحة." }, 400);
  }

  const incoming = Array.isArray(body.messages) ? body.messages : [];
  if (!incoming.length || incoming.length > 12) {
    return respond({ error: "أرسل من رسالة واحدة إلى 12 رسالة في كل طلب." }, 400);
  }
  const messages = incoming.map((message) => ({
    role: message.role === "assistant" ? "assistant" : "user",
    content: typeof message.content === "string" ? message.content.slice(0, 4000) : "",
  })).filter((message) => message.content.trim().length > 0);
  if (!messages.length) return respond({ error: "اكتب سؤالك أولاً." }, 400);

  try {
    const upstream = await fetch(aiUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${aiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: aiModel,
        messages: [
          {
            role: "system",
            content: "أنت المساعد الدراسي لبوابة جامعة بني سويف الأهلية. أجب بالعربية المصرية الواضحة عند ملاءمتها، واشرح خطوة بخطوة. لا تخترع مواعيد محاضرات أو معلومات جامعية غير مؤكدة؛ إذا لم تعرف فقل ذلك بوضوح.",
          },
          ...messages,
        ],
        temperature: 0.5,
        max_tokens: 1000,
      }),
    });

    if (!upstream.ok) {
      const details = await upstream.text();
      console.error("AI provider error:", upstream.status, details.slice(0, 400));
      return respond({ error: "المساعد مشغول حالياً. حاول مرة أخرى بعد قليل." }, 502);
    }
    const result = await upstream.json();
    const answer = result?.choices?.[0]?.message?.content;
    if (typeof answer !== "string" || !answer.trim()) {
      return respond({ error: "لم يصل رد صالح من المساعد." }, 502);
    }
    return respond({ answer });
  } catch (error) {
    console.error("AI request failed:", error);
    return respond({ error: "تعذر الاتصال بالمساعد حالياً." }, 502);
  }
});
