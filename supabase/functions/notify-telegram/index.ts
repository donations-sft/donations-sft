// Sends a Telegram message to the trust's admin chat when a new receipt is saved.
// Secrets required (set via `supabase secrets set`):
//   TELEGRAM_BOT_TOKEN - bot token from BotFather, created for this trust
//   TELEGRAM_CHAT_ID   - chat id that should receive alerts

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const { receipt_no, donor_name, amount, payment_mode, purpose } = await req.json();

    const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
    const chatId = Deno.env.get("TELEGRAM_CHAT_ID");

    if (!botToken || !chatId) {
      return new Response(JSON.stringify({ error: "Telegram not configured" }), { status: 500 });
    }

    const text =
      `New Donation Receipt\n` +
      `No: ${receipt_no}\n` +
      `Donor: ${donor_name}\n` +
      `Amount: Rs. ${amount}\n` +
      `Mode: ${payment_mode}\n` +
      `Head: ${purpose}`;

    const tgRes = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text }),
    });

    if (!tgRes.ok) {
      const errText = await tgRes.text();
      return new Response(JSON.stringify({ error: errText }), { status: 502 });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 400 });
  }
});
