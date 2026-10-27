import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, PutObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const s3 = new S3Client({
  region: "auto",
  endpoint: `https://${Deno.env.get("CF_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID") || "",
    secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY") || "",
  },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") || "",
      Deno.env.get("SUPABASE_ANON_KEY") || "",
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error } = await supabase.auth.getUser();
    if (error || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { folder, filename } = await req.json();
    if (!folder || !filename) {
      return new Response(JSON.stringify({ error: "Missing folder or filename" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Tenant-isolated key: stores/{store_id}/{folder}/{filename}
    const objectKey = `stores/${user.id}/${folder}/${filename}`;

    const command = new PutObjectCommand({
      Bucket: Deno.env.get("R2_BUCKET_NAME") || "rentledger",
      Key: objectKey,
      ContentType: "image/webp",
    });

    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 60 });
    const publicDomain = Deno.env.get("R2_PUBLIC_DOMAIN") || "https://pub-rentledger.r2.dev";
    const publicUrl = `${publicDomain}/${objectKey}`;

    return new Response(JSON.stringify({ uploadUrl, publicUrl }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
