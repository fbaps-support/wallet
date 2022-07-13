[% INCLUDE "header.tpl" %]
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<table class="formtable">
<tr><td>Description:</td><td>
    [%~ details.description ~%]</td></tr>
<tr><td>Tags:</td><td>
    [%~ IF details.tags.size == 0 ~%]
    	-
    [%~ ELSE ~%]
	[%~ FOREACH tag IN details.tags ~%]
	    [%~ tag ~%]
	    [%~ IF !loop.last() ~%]
	    	, 
	    [%= END ~%]
	[%~ END ~%]
    [%~ END ~%]
</td></tr>
<tr><td>Expiry time (weeks):</td><td>
    [%~ IF details.expiry_weeks < 1 ~%]
    	None
    [%~ ELSE ~%]
	[%~ details.expiry_weeks ~%]
    [%~ END ~%]</td></tr>
<tr><td>Last Changed:</td>
    <td [% IF ((details.expiry_weeks != 0 && details.weeks > details.expiry_weeks) || details.insecure) %]class="warning"[% END %]>
	[% details.last_changed %] ([% details.weeks %] week[% IF details.weeks != 1 %]s[% END %] ago)
	[% IF details.insecure %]-- Marked INSECURE[% END %] </td></tr>
<tr><td>Ownership:</td><td>
	[% FOREACH owner IN details.owners %]
		[%= owner.username =%]
	[% END %]
</td></tr>
<tr><td>Have access:</td><td>
	[% FOREACH user IN details.users %]
		[%= user.username =%]
	[% END %]
</td></tr>
<tr><td>Your wallet password:</td>
    <td><input type="password" name="password" size="20">
        <input type="submit" name="retrieve" value="Retrieve">
[%~ IF is_owner -%]
        <input type="submit" name="edit" value="Edit">
        <input type="submit" name="delete" value="Delete">
[%- END -%]
    </td>
</tr>
</table>
</form>
[% INCLUDE "footer.tpl" %]
