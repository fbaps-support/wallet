[% INCLUDE "header.tpl" %]
<p>
<form method="POST" accept-charset="utf-8">
<input type="hidden" name="trackstate" value="[% trackstate %]">
Modifying access for <b>
[% FOREACH user IN userlist %][% user.0 %][% IF !loop.last %], [% END %][% END %]</b>. 
Don't forget to save changes.<br>
Your wallet password: 
<input type="password" name="password" size="20">
<input type="submit" value="Save Changes">
<p>
<table class="realtable">
<tr><th>Description</th>
[% FOREACH user IN userlist %]<th>[% user.0 %]</th>[% END %]</tr> 
[% FOREACH access ~%]
	<tr>
	<td>[% description %]</td>
[% FOREACH user IN userlist %]
	<td align="center">
	<input type="checkbox" name="access.[% user.1 %].[% ID %]" 
		[%~ IF access.item(user.0) %] checked[% END %]
		[%~ IF access.item(user.0).1 %] disabled[% END %]
	>
	</td>
[% END %]
	</tr>
[%~ END ~%]
</table>
</form>
[% INCLUDE "footer.tpl" %]
