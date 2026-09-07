// Validation de la configuration fournisseur et barrière local-only. Cette
// bibliothèque ne résout aucun nom : le mode local n'accepte que des littéraux
// loopback, ce qui exclut les rebonds DNS et les autorités trompeuses.

.pragma library

function parseEndpoint(value) {
    const text = String(value || "").trim();
    const match = /^(https?):\/\/([^\/?#]+)(?:[\/?#].*)?$/i.exec(text);
    if (!match)
        return { ok: false, error: "l'endpoint doit être une URL HTTP ou HTTPS complète" };

    const authority = match[2];
    if (!authority || authority.indexOf("@") !== -1)
        return { ok: false, error: "l'endpoint ne doit pas contenir d'identifiants" };

    let hostname = "";
    let port = "";
    if (authority.startsWith("[")) {
        const closing = authority.indexOf("]");
        if (closing < 0)
            return { ok: false, error: "adresse IPv6 non terminée" };
        hostname = authority.slice(1, closing).toLowerCase();
        const suffix = authority.slice(closing + 1);
        if (suffix) {
            if (!suffix.startsWith(":"))
                return { ok: false, error: "autorité d'endpoint invalide" };
            port = suffix.slice(1);
        }
    } else {
        const parts = authority.split(":");
        if (parts.length > 2)
            return { ok: false, error: "une adresse IPv6 doit être entre crochets" };
        hostname = parts[0].toLowerCase();
        port = parts.length === 2 ? parts[1] : "";
    }

    if (!hostname)
        return { ok: false, error: "hôte d'endpoint vide" };
    if (port) {
        if (!/^[0-9]{1,5}$/.test(port))
            return { ok: false, error: "port d'endpoint invalide" };
        const portNumber = Number(port);
        if (portNumber < 1 || portNumber > 65535)
            return { ok: false, error: "port d'endpoint hors limites" };
    }
    return { ok: true, scheme: match[1].toLowerCase(), hostname: hostname };
}

function isIpv4Loopback(hostname) {
    const parts = String(hostname || "").split(".");
    if (parts.length !== 4 || parts[0] !== "127")
        return false;
    for (let i = 0; i < parts.length; i++) {
        if (!/^[0-9]{1,3}$/.test(parts[i]))
            return false;
        const value = Number(parts[i]);
        if (value < 0 || value > 255)
            return false;
    }
    return true;
}

function isLocalEndpoint(value) {
    const parsed = parseEndpoint(value);
    if (!parsed.ok)
        return false;
    return parsed.hostname === "localhost"
        || parsed.hostname === "::1"
        || isIpv4Loopback(parsed.hostname);
}

function validateEndpoint(value, localOnly) {
    const parsed = parseEndpoint(value);
    if (!parsed.ok)
        return parsed;
    if (localOnly && !isLocalEndpoint(value)) {
        return {
            ok: false,
            error: "Le mode local uniquement refuse cet endpoint distant."
        };
    }
    return parsed;
}

function validateCatalog(text) {
    const raw = String(text || "");
    if (!raw.trim())
        return { ok: false, error: "configuration fournisseur vide" };
    if (raw.length > 65536)
        return { ok: false, error: "configuration fournisseur supérieure à 64 Kio" };

    let document;
    try {
        document = JSON.parse(raw);
    } catch (error) {
        return { ok: false, error: "JSON fournisseurs invalide : " + error };
    }
    if (!document || Array.isArray(document) || typeof document !== "object")
        return { ok: false, error: "la configuration doit être un objet JSON" };
    if (document.schema_version !== 1)
        return { ok: false, error: "schema_version fournisseurs non supportée" };
    if (!/^20[0-9]{2}-[0-9]{2}-[0-9]{2}$/.test(String(document.updated || "")))
        return { ok: false, error: "date updated fournisseurs invalide" };
    if (!Array.isArray(document.providers)
            || document.providers.length < 1 || document.providers.length > 32) {
        return { ok: false, error: "la configuration doit contenir de 1 à 32 fournisseurs" };
    }

    const requiredKeys = ["base_url", "format", "id", "model", "name", "requires_key"];
    const ids = ({});
    const names = ({});
    const providers = [];
    for (let i = 0; i < document.providers.length; i++) {
        const provider = document.providers[i];
        if (!provider || Array.isArray(provider) || typeof provider !== "object")
            return { ok: false, error: "fournisseur " + i + " invalide" };
        const keys = Object.keys(provider).sort();
        if (JSON.stringify(keys) !== JSON.stringify(requiredKeys)) {
            return { ok: false, error: "champs inattendus ou manquants pour le fournisseur " + i };
        }

        const id = String(provider.id || "");
        const name = String(provider.name || "").trim();
        const baseUrl = String(provider.base_url || "").trim();
        const format = String(provider.format || "");
        const model = String(provider.model || "").trim();
        if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(id))
            return { ok: false, error: "id fournisseur invalide : " + id };
        if (!name || name.length > 80)
            return { ok: false, error: "nom fournisseur invalide : " + id };
        if (!model || model.length > 256)
            return { ok: false, error: "modèle fournisseur invalide : " + id };
        if (format !== "openai" && format !== "anthropic")
            return { ok: false, error: "format fournisseur invalide : " + id };
        if (typeof provider.requires_key !== "boolean")
            return { ok: false, error: "requires_key doit être booléen : " + id };
        const endpoint = validateEndpoint(baseUrl, false);
        if (!endpoint.ok)
            return { ok: false, error: "endpoint " + id + " : " + endpoint.error };
        if (ids["id:" + id] || names["name:" + name])
            return { ok: false, error: "id ou nom fournisseur dupliqué : " + id };
        ids["id:" + id] = true;
        names["name:" + name] = true;
        providers.push({
            id: id,
            name: name,
            baseUrl: baseUrl,
            format: format,
            model: model,
            requiresKey: provider.requires_key,
            local: isLocalEndpoint(baseUrl)
        });
    }
    return { ok: true, providers: providers, updated: document.updated };
}
