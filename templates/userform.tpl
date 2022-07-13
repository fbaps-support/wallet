[% INCLUDE "header.tpl" %]
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">

<table class="realtable">
<tr><th>Username</th><th>Password set?</th><th>User admin?</th><th>Emergency admin?</th><th>&nbsp;</th></tr>
[% FOREACH user IN userlist ~%]
<tr>
    <td>[% user.username %]</td>
    <td>[% IF (user.publickey != "") %]Yes[% ELSE %]No[% END %]</td>
    <td><input type="submit" name="uatoggle[% user.ID %]" value="[% IF user.useradmin %]Yes[% ELSE %]No[% END %]"></td>
    <td><input type="submit" name="eatoggle[% user.ID %]" value="[% IF user.emergencyadmin %]Yes[% ELSE %]No[% END %]"></td>
    <td>
	<input type="submit" name="deluser[% user.ID %]" value="Delete user access">
	<input type="submit" name="reset[% user.ID %]" value="Reset password">
    </td>
</tr>
[%~ END %]
</table>
</form>
[% INCLUDE "footer.tpl" %]
