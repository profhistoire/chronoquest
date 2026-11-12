import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Méthode non autorisée." });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse(401, { success: false, error: "Connexion enseignant requise." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
    return jsonResponse(500, { success: false, error: "Configuration serveur incomplète." });
  }

  const enseignantClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: utilisateurConnecte, error: erreurSession } =
    await enseignantClient.auth.getUser(authorization.slice("Bearer ".length));
  if (erreurSession || !utilisateurConnecte.user) {
    return jsonResponse(401, { success: false, error: "Session invalide ou expirée." });
  }

  const { data: estEnseignant, error: erreurAutorisation } =
    await enseignantClient.rpc("is_hub_teacher");
  if (erreurAutorisation) {
    console.error("Teacher authorization check failed.");
    return jsonResponse(500, { success: false, error: "Vérification du compte enseignant impossible." });
  }
  if (estEnseignant !== true) {
    return jsonResponse(403, { success: false, error: "Action réservée au compte enseignant autorisé." });
  }

  if (Number(request.headers.get("Content-Length") || 0) > 4096) {
    return jsonResponse(413, { success: false, error: "Requête trop volumineuse." });
  }

  let corps: unknown;
  try {
    corps = await request.json();
  } catch {
    return jsonResponse(400, { success: false, error: "Requête JSON invalide." });
  }
  if (!corps || typeof corps !== "object" || Array.isArray(corps)) {
    return jsonResponse(400, { success: false, error: "Données de réinitialisation invalides." });
  }

  const donnees = corps as Record<string, unknown>;
  const email = typeof donnees.email === "string" ? donnees.email.trim().toLocaleLowerCase("fr") : "";
  const password = typeof donnees.password === "string" ? donnees.password : "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jsonResponse(400, { success: false, error: "Adresse e-mail invalide." });
  }
  if (password.length < 12 || password.length > 128) {
    return jsonResponse(400, { success: false, error: "Le mot de passe doit contenir entre 12 et 128 caractères." });
  }

  const { data: eleve, error: erreurListe } = await enseignantClient
    .from("student_roster")
    .select("email")
    .eq("email", email)
    .maybeSingle();
  if (erreurListe) {
    console.error("Student roster verification failed.");
    return jsonResponse(500, { success: false, error: "Vérification de la liste des élèves impossible." });
  }
  if (!eleve) {
    return jsonResponse(404, { success: false, error: "Cet élève ne figure pas dans la liste autorisée." });
  }

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const taillePage = 1000;
  let idUtilisateur: string | null = null;
  for (let page = 1; ; page += 1) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({
      page,
      perPage: taillePage,
    });
    if (error) {
      console.error("Supabase Auth user lookup failed.");
      return jsonResponse(500, { success: false, error: "Recherche du compte élève impossible." });
    }

    const utilisateur = data.users.find(
      candidat => candidat.email?.toLocaleLowerCase("fr") === email,
    );
    if (utilisateur) {
      idUtilisateur = utilisateur.id;
      break;
    }
    if (data.users.length < taillePage) break;
  }
  if (!idUtilisateur) {
    return jsonResponse(404, { success: false, error: "Aucun compte Supabase Auth ne correspond à cet élève." });
  }

  const { error: erreurMiseAJour } = await supabaseAdmin.auth.admin.updateUserById(
    idUtilisateur,
    { password },
  );
  if (erreurMiseAJour) {
    console.error("Supabase Auth password update failed.");
    return jsonResponse(500, { success: false, error: "Mise à jour du mot de passe impossible." });
  }

  return jsonResponse(200, { success: true });
});
