[% INCLUDE "header.tpl" %]
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
Please confirm you wish to delete the following credential from the wallet:
<b>[% details.description %]</b>
<input type="submit" name="confirmdelete" value="Confirm">
</form>
[% INCLUDE "footer.tpl" %]
