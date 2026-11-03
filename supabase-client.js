const SUPABASE_URL = "https://viwjorxosigtexcgiabx.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_DdY1LaD_QE5wtuKrjSvZQw_zoJYnp4c";

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function getMyProfile() {
  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabaseClient
    .from("profiles")
    .select("id, full_name, role, active, is_super_admin")
    .eq("id", user.id)
    .single();
  if (error) {
    console.error("getMyProfile failed:", error.message);
    throw error;
  }
  return data;
}

async function requireRole(allowedRoles) {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    window.location.href = "./index.html";
    return null;
  }
  let profile;
  try {
    profile = await getMyProfile();
  } catch (e) {
    window.location.href = "./index.html";
    return null;
  }
  if (!profile || !allowedRoles.includes(profile.role) || profile.active === false) {
    if (profile && profile.active === false) await supabaseClient.auth.signOut();
    window.location.href = "./index.html";
    return null;
  }
  return profile;
}
