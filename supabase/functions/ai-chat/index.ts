// Supabase Edge Function: ai-chat
// Deploy with verify_jwt enabled. Set AI_API_URL, AI_API_KEY, and AI_MODEL
// as Supabase function secrets. Never put the provider key in the website.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://ahmed526548.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const aiUrl = Deno.env.get("AI_API_URL");
    const aiKey = Deno.env.get("AI_API_KEY");
    const aiModel = Deno.env.get("AI_MODEL");
    if (!supabaseUrl || !anonKey || !aiUrl || !aiKey || !aiModel) {
      return new Response(JSON.stringify({ error: "AI service is not configured yet." }), { status: 503, headers: corsHeaders });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Authentication required." }), { status: 401, headers: corsHeaders });
    }
    const supabase = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid session." }), { status: 401, headers: corsHeaders });
    }

    const body = await req.json();
    const messages = Array.isArray(body.messages) ? body.messages : [];
    if (!messages.length || messages.length > 20) {
      return new Response(JSON.stringify({ error: "Send between 1 and 20 messages." }), { status: 400, headers: corsHeaders });
    }
    const safeMessages = messages.map((m: { role?: string; content?: string }) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      content: typeof m.content === "string" ? m.content.slice(0, 6000) : "",
    })).filter((m: { content: string }) => m.content.trim().length > 0);
    if (!safeMessages.length) return new Response(JSON.stringify({ error: "Message is empty." }), { status: 400, headers: corsHeaders });

    const upstream = await fetch(aiUrl, {
      method: "POST",
      headers: { "Authorization": `Bearer ${aiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: aiModel,
        messages: [
          { role: "system", content: "أنت المساعد الدراسي لبوابة جامعة بني سويف الأهلية. أجب بالعربية المصرية الواضحة عند ملاءمتها، واشرح خطوة بخطوة، ولا تخترع مواعيد أو معلومات جامعية غير مؤكدة. إذا لم تعرف فقل ذلك بوضوح." },
          ...safeMessages,
        ],
        temperature: 0.5,
        max_tokens: 1200,
      }),
    });
    const result = await upstream.json().catch(() => ({}));
    if (!upstream.ok) {
      return new Response(JSON.stringify({ error: "AI provider request failed." }), { status: 502, headers: corsHeaders });
    }
    const answer = result?.choices?.[0]?.message?.content;
    if (typeof answer !== "string" || !answer.trim()) {
      return new Response(JSON.stringify({ error: "AI provider returned no answer." }), { status: 502, headers: corsHeaders });
    }
    return new Response(JSON.stringify({ answer }), { status: 200, headers: corsHeaders });
  } catch (_error) {
    return new Response(JSON.stringify({ error: "Unexpected server error." }), { status: 500, headers: corsHeaders });
  }
});
