[% INCLUDE "header.tpl" %]
[% INCLUDE "userlist.js" %]

<p>
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<div id="modlist">You need JavaScript enabled for this to work</div><br>
<input type="submit" value="Go">
</form>

<script type="text/javascript">
var users = new Array(
[% FOREACH username IN userlist %]
	new Array("[% username.0 %]", [% username.1 %], 0)[% IF !loop.last %],[% END %]
[% END %]
);
createselect("modlist", "user", "Select people to modify", users, null);
</script>
[% INCLUDE "footer.tpl" %]
