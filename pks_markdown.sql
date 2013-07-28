--------------------------------------------------------
--  File created - zaterdag-juli-13-2013   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package MARKDOWN
--------------------------------------------------------

  CREATE OR REPLACE PACKAGE MARKDOWN as 
  function markdown_to_html(p_text in clob)
  return clob;
  
  function html_to_markdown(p_text in varchar2)
  return varchar2;

end markdown;

/
