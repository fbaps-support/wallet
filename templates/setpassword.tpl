[% INCLUDE "header.tpl" %]
You have not yet set a password for your private key. No use can
be made of the wallet until you've done this. Please choose a password
below:
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
<table class="formtable">
<tr><th>Password:</th><td><input type="password" name="password1" width=20></td></tr>
<tr><th>Again:</th><td><input type="password" name="password2" width=20></td></tr>
<tr><td colspan="2"><input type="submit" name="setpass" value="Set password"></td></tr>
</table>
</form>
[% INCLUDE "footer.tpl" %]
