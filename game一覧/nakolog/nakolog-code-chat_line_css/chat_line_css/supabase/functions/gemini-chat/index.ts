import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  try {
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) return json({ error: "SupabaseにGEMINI_API_KEYが設定されていません。" }, 500);
    const body = await req.json();
    const messages = Array.isArray(body.messages) ? body.messages : [];
    const contents = messages
      .filter((m: any) => ["user", "assistant"].includes(m?.role) && typeof m?.content === "string")
      .slice(-16)
      .map((m: any) => {
        const parts: any[] = [{ text: m.content.slice(0, 6000) }];
        if (m.role === "user" && typeof m.imageDataUrl === "string") {
          const match = /^data:(image\/(?:jpeg|png|webp|gif));base64,([A-Za-z0-9+/=]+)$/i.exec(m.imageDataUrl);
          if (match) parts.push({ inlineData: { mimeType: match[1], data: match[2] } });
        }
        return { role: m.role === "assistant" ? "model" : "user", parts };
      });
    if (!contents.length || contents[contents.length - 1].role !== "user") return json({ error: "メッセージを入力してください。" }, 400);
    const response = await fetch("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent", {
      method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": geminiKey },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: "あなたは『うさきち』という親しみやすい日本語のAIチャット相手です。わかりやすく、丁寧で、年齢に配慮した安全な返答をしてください。必要に応じて絵文字を使い、簡潔に答えてください。" }] },
        contents, generationConfig: { temperature: 0.7, maxOutputTokens: 900 },
      }),
    });
    const result = await response.json();
    if (!response.ok) {
      const providerMessage = result?.error?.message || "Gemini APIがリクエストを拒否しました。";
      console.error("Gemini API error", response.status, providerMessage);
      return json({ error: `Gemini API status ${response.status}: ${providerMessage}` }, response.status === 503 ? 503 : 502);
    }
    const reply = result?.candidates?.[0]?.content?.parts?.map((p: any) => p.text || "").join("").trim();
    if (!reply) return json({ error: "Geminiから返答を取得できませんでした。" }, 502);
    return json({ reply });
  } catch (e) {
    console.error("gemini-chat failed", e);
    return json({ error: "リクエストを処理できませんでした。" }, 500);
  }
});
