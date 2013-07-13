create or replace 
package markdown as 
  function markdown_to_html(p_text in varchar2)
  return varchar2;
  
  function html_to_markdown(p_text in varchar2)
  return varchar2;

end markdown;