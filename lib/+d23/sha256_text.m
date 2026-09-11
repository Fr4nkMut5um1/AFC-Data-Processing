function value = sha256_text(text_value)
%SHA256_TEXT SHA-256 digest for UTF-8 text.
bytes = unicode2native(char(text_value), 'UTF-8');
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(bytes);
raw = typecast(digest.digest(), 'uint8');
value = lower(reshape(dec2hex(raw, 2).', 1, []));
end
