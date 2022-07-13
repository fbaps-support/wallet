[% INCLUDE "header.tpl" %]
<script type="text/javascript">
[% INCLUDE "sha1.js" %]
function totp(secret, digits, slotlen) 
{
	// Couple of defaults.
	digits = (typeof digits === 'undefined') ? 6 : digits;
	slotlen = (typeof slotlen === 'undefined') ? 30 : slotlen;

	// Base32 decode the secret.
	var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
	var bits = 0;
	var numbits = 0;
	var key = "";
	for(var i = 0; i < secret.length; i++) 
	{
		var pos = alphabet.indexOf(secret.charAt(i).toUpperCase());
		if (pos >= 0)
		{
			bits = (bits << 5) | pos;
			numbits += 5;
			if (numbits >= 8)
			{
				var c = bits >> (numbits - 8);
				bits = bits ^ (c << (numbits - 8))
				key = key + String.fromCharCode(c);
				numbits -= 8;
			}
		}
	}
	// Pick up any leftovers. I suspect this is not needed for any valid base32 string.
	if (numbits > 0)
	{
		key = key + String.fromCharCode(bits & 0xFF);
	}

	// Make HMAC object
	var h = new jsSHA("SHA-1", "HEX", { hmacKey: { value: key, format: "BYTES" } });

	// Retrieve the slot number (hex encoded and padded to 16 characters) and TTL.
	var time = Math.floor(new Date().getTime() / 1000);
	var slot = ("0000000000000000" + Math.floor(time/slotlen).toString(16)).substr(-16);
	var ttl = slotlen - (time % slotlen);

	// Add the hex-encoded slot number to the HMAC.
	h.update(slot);

	// Retrieve its value.
	var hmac = h.getHash("HEX");

	// The last nybble of the HMAC is used as an offset into the
	// rest to extract the TOTP code.
	var offset = parseInt(hmac.substr(-1), 16);
	var otp = parseInt(hmac.substr(offset*2, 8), 16) & 0x7FFFFFFF;

	// Return the code, suitably padded. digits can't meaningfully
	// be greater than 10, so cheat with the padding.
	return [("0000000000" + otp.toString()).substr(-digits), ttl];
}

function updateOTP(secret, id)
{
	 var [code, ttl] = totp(secret);
	 document.getElementById("copy"+id).value = code;
	 document.getElementById("totp"+id).innerHTML = "OTP Code: " + code + "   ("+ttl+")";
	 setTimeout("updateOTP('"+secret+"', '" + id + "')", 1000);
}

function copy(id) {
	var content = document.getElementById(id);
	content.select();
	document.execCommand("copy");
}
</script>
The credential details are below: <P>

[% credentials | make_links_and_escape %]
[% INCLUDE "footer.tpl" %]
