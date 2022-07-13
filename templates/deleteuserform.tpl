[% INCLUDE "header.tpl" %]
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
Please confirm you wish to delete the following user from the wallet:
<b>[% user.username %]</b>
<input type="submit" name="confirmdelete" value="Confirm">
</form>
[% INCLUDE "footer.tpl" %]
