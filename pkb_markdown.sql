create or replace 
package body markdown as

  type reference_record_type is record (src varchar2(100)
                                       ,title varchar2(800)
                                       );
  
  type reference_table_type is table of reference_record_type
  index by varchar2(100);
  
  /*Define some special characters as constants so we know what they are*/
  c_new_line        constant varchar(1) := chr(10);
  c_carriage_return constant varchar(1) := chr(13);
  c_space           constant varchar(1) := chr(32);
  c_tab             constant varchar(1) := chr(9);
  
  g_in_list                  boolean    := false;
  
  function replace_line(p_text in clob)
  return clob
  as
    v_text            clob := p_text;
  begin
    /*Line with --- */
    v_text := regexp_replace(v_text
                            ,'^(.{0,})'||c_new_line||'-{3,}$'
                            ,'\1'||c_new_line||'<hr/>'
                            ,1
                            ,0
                            ,'m'
                            );
    /*Line with * _ with and without spaces between and - with spaces between */                        
    v_text := regexp_replace(v_text
                            ,'^((- ){3,}-{0,1}$)|((- ){2}-$)|((\* ){3,}\*{0,1}$)|((\* ){2}\*$)|((_ ){3,}_{0,1}$)|((_ ){2}_$)|[*_]{3,}$'
                            ,'<hr/>'
                            ,1
                            ,0
                            ,'m'
                            );
    return v_text;
  end;
  
  function replace_header(p_text in clob)
  return clob
  as
    v_text            clob := p_text;
  begin
    /*Find a header there are maximum of 6 levels*/
    for i in reverse 1..6
    loop
      v_text := regexp_replace(regexp_replace(v_text
                                             ,'^(#{'||i||'})(.{1,})$'
                                             ,'<h'||i||'>\2</h'||i||'>'
                                             ,1
                                             ,0
                                             ,'m'
                                             )
                              ,'#*</h'||i||'>'
                              ,'</h'||i||'>'
                              ,1
                              ,0
                              ,'m'
                              );
    end loop;
    /*Header with underline*/
    v_text := regexp_replace(v_text
                            ,'(^.*)['||c_new_line||']={3,}$'
                            ,'<h1>\1</h1>'
                            ,1
                            ,0
                            ,'m'
                            );
    v_text := regexp_replace(v_text
                            ,'^(.{1,})['||c_new_line||']-{3,}$'
                            ,'<h2>\1</h2>'
                            ,1
                            ,0
                            ,'m'
                            );
    return v_text;
  end;
  
  function replace_bold_italic(p_text in clob)
  return clob
  as
    v_text            clob := p_text;
  begin
    /*Bold*/
    v_text := regexp_replace(regexp_replace(v_text
                                           ,'[*_]{2}(\w{1,})[*_]{2}'
                                           ,'<strong>\1</strong>'
                                           ,1
                                           ,0
                                           ,'m'
                                           )
                            ,'[*_]{2}(\w{1,}.+\w{1,})[*_]{2}'
                            ,'<strong>\1</strong>'
                            ,1
                            ,0
                            ,'m'
                            );
   
    /*Italic*/
    v_text := regexp_replace(regexp_replace(v_text
                                           ,'[*_]{1}(\w{1,})[*_]{1}'
                                           ,'<em>\1</em>'
                                           ,1
                                           ,0
                                           ,'m'
                                           )
                            ,'[*_]{1}(\w{1,}.+\w{1,})[*_]{1}'
                            ,'<em>\1</em>'
                            ,1
                            ,0
                            ,'m'
                            );
    v_text := replace(v_text,'\*','*');
    v_text := replace(v_text,'\_','_');
    return v_text;
  end;
  
  function replace_inline_code(p_text in clob)
  return clob
  as
    c_block_character constant varchar2(1) := chr(176);
    v_text            clob := p_text;
    v_start_position  number;
    v_end_position    number;
  begin
    /*Code between double backticks tickets*/
    v_start_position := instr(v_text,'``',1,1);
    loop
      exit when v_start_position = 0;
      v_end_position := instr(v_text,'``',v_start_position+2,1);
      if v_end_position != 0
      then
        /*Escape the code 
        **Replace the backtick so not to interact with other inline code
        **Place the escaped code between code tags in the text
        */
        v_text := substr(v_text,1,v_start_position-1)
              || '<code>'
              || replace(sys.htf.escape_sc(substr(v_text
                                                 ,v_start_position+2
                                                 ,v_end_position-v_start_position-2
                                                 )
                                          )
                        ,'`'
                        ,c_block_character
                        )
              || '</code>'
              || substr(v_text,v_end_position+2)
              ;
        v_start_position := instr(v_text,'``',1,1);
      else
        v_start_position := v_end_position;
      end if;  
    end loop;
    
    /*Code between single backticks*/
    v_start_position := instr(v_text,'`',1,1);
    loop
      exit when v_start_position = 0;
      v_end_position := instr(v_text,'`',v_start_position+1,1);
      if v_end_position != 0
      then
        /*Escape the code
        **Place the escaped code between code tags in the text
        */
        v_text := substr(v_text,1,v_start_position-1)
              || '<code>'
              || sys.htf.escape_sc(substr(v_text
                                         ,v_start_position+1
                                         ,v_end_position-v_start_position-1
                                         )
                                  )
              || '</code>'
              || substr(v_text,v_end_position+1);
        v_start_position := instr(v_text,'`',1,1);
      else
        v_start_position := v_end_position;
      end if;  
    end loop;
    /*Place the backticks inside the code back*/
    v_text := replace(v_text,c_block_character,'`');
    return v_text;
  end;
  
  function replace_new_line(p_text in clob)
  return clob
  is
  begin
    return regexp_replace(p_text,' {2,}$',' <br />',1,1,'m');
  end;
  
  procedure get_references(p_text in out clob
                          ,p_reference_table  out reference_table_type
                          )
  is
    c_pattern         varchar2(100) := '^ {0,3}\[\w{1,}\]:('||c_space||'|'||c_tab||'){1,}(\w|/|/|:|\.|-){1,}(\s{1,}["''(](\w| ){1,}["'')]){0,1}$'; 
    v_text            clob := p_text;
    v_reference       varchar2(1000);
    v_reference_table reference_table_type;
    v_index           varchar2(100);
    v_source          varchar2(200);
  begin
    v_reference := regexp_substr(v_text,c_pattern,1,1,'m');
    loop
      exit when v_reference is null;
      /*Split the reference up in the index, source en title*/
      v_index :=  upper(ltrim(rtrim(regexp_substr(v_reference,'\[.*\]'),']'),'['));
      v_reference_table(v_index).src := regexp_substr(v_reference,'(\w|/|/|:|\.|-){1,}',1,3);
      v_reference_table(v_index).title := regexp_substr(v_reference,'["''(](\w| ){1,}["'')]$');
      v_reference_table(v_index).title := substr(v_reference_table(v_index).title,2,length(v_reference_table(v_index).title)-2);
      /*Remove the reference by replacing it with null*/
      v_text := regexp_replace(v_text,c_pattern,null,1,1,'m');
      /*Get the next reference*/                        
      v_reference := regexp_substr(v_text,c_pattern,1,1,'m');
    end loop;
    p_text := v_text;
    p_reference_table := v_reference_table;
  end;
  
  function replace_references(p_text in clob
                             ,p_reference_table in reference_table_type
                             )
  return clob
  is
    c_link_pattern    constant varchar2(50) := '\[[a-zA-Z0-9-_ '']{1,}\]\[[a-zA-Z0-9-_ '']{1,}\]';
    v_text            clob := p_text;
    v_reference_table reference_table_type := p_reference_table;
    v_occurance       number;
    v_index           varchar2(100);
    v_link            varchar2(200);
    v_link_text       varchar2(200);
    v_title           varchar2(900);
  begin
    /*Replace a image*/
    v_link := regexp_substr(v_text,'!\[(\w|\s){1,}\] {0,1}\[(\w|\s){1,}\]',1,1,'m');
    v_occurance := 1;
    loop
      exit when v_link is null;
      v_index := upper(substr(v_link,instr(v_link,'[',1,2)+1,instr(v_link,']',1,2)-instr(v_link,'[',1,2)-1));
      if v_index is null
      then
        v_index := upper(substr(v_link,instr(v_link,'[',1,1)+1,instr(v_link,']',1,1)-instr(v_link,'[',1,1)-1));
        v_link_text := v_index;
      else
        v_link_text := substr(v_link,instr(v_link,'[',1,1)+1,instr(v_link,']',1,1)-instr(v_link,'[',1,1)-1);
      end if;
      if v_reference_table.exists(v_index)
      then
        /*The reference is found replace it*/
        v_text := regexp_replace(v_text
                                ,'!\[(\w|\s){1,}\] {0,1}\[(\w|\s){1,}\]'
                                ,'<img src="'||v_reference_table(v_index).src||'" alt="'||v_link_text||'" title="'||v_reference_table(v_index).title||'" />'
                                ,1
                                ,1
                                );
      else
        /*The reference is not found leave it in and go on*/
        v_occurance := v_occurance +1;
      end if;                          
      v_link := regexp_substr(v_text,'!\[(\w|\s){1,}\] {0,1}\[(\w|\s){1,}\]',1,v_occurance,'m');                        
    end loop;
    /*Replace the links*/
    --v_link := regexp_substr(v_text,'\[\w{1,}\] {0,1}\[\w{0,}\]',1,1,'m');
    v_link := regexp_substr(v_text,c_link_pattern,1,1,'m');
    v_occurance := 1;
    loop
      exit when v_link is null;
      v_index := upper(substr(v_link,instr(v_link,'[',1,2)+1,instr(v_link,']',1,2)-instr(v_link,'[',1,2)-1));
      if v_index is null
      then
        v_index := upper(substr(v_link,instr(v_link,'[',1,1)+1,instr(v_link,']',1,1)-instr(v_link,'[',1,1)-1));
        v_link_text := v_index;
      else
        v_link_text := substr(v_link,instr(v_link,'[',1,1)+1,instr(v_link,']',1,1)-instr(v_link,'[',1,1)-1);
      end if;
      if v_reference_table.exists(v_index)
      then
        /*The reference is found replace it*/
        if v_reference_table(v_index).title is not null
        then
          v_title := ' title="'||v_reference_table(v_index).title||'"' ;
        end if;
        v_text := replace (v_text
                          ,v_link
                          ,'<a href="'||v_reference_table(v_index).src||'"'||v_title||'>'||v_link_text||'</a>'
                          );
      else
        /*The reference is not found leave it and go on*/
        v_occurance := v_occurance +1;
      end if;                          
      v_link := regexp_substr(v_text,c_link_pattern,1,v_occurance,'m');                        
    end loop;
    return v_text;
  end;
  
  function replace_image(p_text in clob)
  return clob
  is
    v_text   clob := p_text;
  begin
    /*Inline image with title*/
    v_text := regexp_replace(v_text
                            ,'!\[(.{1,})\]\((.{1,}) "(.{1,})"\)'
                            ,'<img src="\2" alt="\1" title="\3" />'
                            ,1,1,'m' );
    /*Inline image without a title*/                        
    v_text := regexp_replace(v_text
                            ,'!\[(.{1,})\](\(.{1,})\)'
                            ,'<img src="\2" alt="\1" />'
                            ,1,1,'m' );       
    return v_text;                        
  end;
  
  function replace_link(p_text in clob)
  return clob
  is
    v_text clob := p_text;
  begin
    /*Inline link with title*/
    v_text := regexp_replace(v_text
                            ,'\[(.{1,})\]\((.{1,}) "(.{1,})"\)'
                            ,'<a href="\2" title="\3">\1</a>'
                            ,1,1,'m' );
    /*Inline link without a title*/                        
    v_text := regexp_replace(v_text
                            ,'\[(.{1,})\](\(.{1,})\)'
                            ,'<a href="\2">\1</a>'
                            ,1,1,'m' );
    return v_text;                        
  end;
    
  function markdown_to_html(p_text in clob)
  return clob
  as
    cursor c_lines(b_text in clob)
    is
      select substr(txt, 
              instr(txt, c_new_line, 1, level) + 1,
              instr(txt, c_new_line, 1, level + 1) - instr(txt,c_new_line, 1, level)-1) as line
      from   (select c_new_line||b_text||c_new_line txt from dual)
      connect by level <= length(b_text) - length(replace(b_text, c_new_line, '')) + 1
    ;
    type lines_table_type is table of c_lines%rowtype
    index by pls_integer;
    
    type block_record_type is record(text clob
                                    ,block_type varchar2(2)
                                    );
    type block_table_type is table of block_record_type
    index by pls_integer;
    
    v_text            clob;
    v_pattern         varchar2(200);
    v_replacement     varchar2(20);
    v_block_table     block_table_type;
    v_lines_table     lines_table_type;
    v_block_number    number;
    v_block_type      varchar(2);
    v_unordered_open  boolean := false;
    v_ordered_open    boolean := false;
    v_reference_table reference_table_type;
  begin
    v_text := p_text;
    v_text := replace(v_text,c_carriage_return||c_new_line,c_new_line);
    v_text := replace_header(v_text);
    v_text := replace_line(v_text);
    get_references(v_text,v_reference_table);
   
    
    /*Defide the text in lines*/
    open  c_lines(v_text);
    fetch c_lines bulk collect
    into  v_lines_table;
    close c_lines;
    
    /*Determine the blocks
    ** 4 spaces or a tab is code
    ** 4 spaces in a list is a text of the list 
    ** > is a quote
    ** n. ordered list
    ** + * - unorderd list
    ** <hr /> a line
    ** <hN> a header 
    */
    for i in v_lines_table.first .. v_lines_table.last
    loop
      v_block_type := case 
                        when regexp_instr(v_lines_table(i).line,'^\s{0,}$')>0
                             or
                             v_lines_table(i).line is null
                        then
                          'B'
                        when regexp_instr(v_lines_table(i).line,'^'||c_space||'{4}|'||c_tab) > 0
                        then
                          'C'
                        when regexp_instr(v_lines_table(i).line,'^>') > 0
                        then
                          'Q'
                        when regexp_instr(v_lines_table(i).line,'^\d{1,}\.('||c_space||'){1,}') > 0
                        then
                          'O'
                        when regexp_instr(trim(v_lines_table(i).line),'^[*+-]{1}'||c_space||'{1,}') > 0
                        then
                          'U'
                        when regexp_instr(v_lines_table(i).line,'^(<hr/>|<h\d{1,}>){1}') > 0
                        then
                          'H'                          
                      else
                        'T'
                      end;
        
      if v_block_table.count = 0
      then
        /*The first block*/
        v_block_number := 1;
        if v_block_type in ('O','U')
        then
          /*List actual line starts at the third character*/
          v_block_table(v_block_number).text := substr(v_lines_table(i).line,3);
        elsif v_block_type = 'Q'
        then
         /*Quote actual line starts at the second character*/
          v_block_table(v_block_number).text := ltrim(substr(v_lines_table(i).line,2));
        elsif v_block_type = 'C'
        then
          /*Code actual line starts after the 4 space or tab*/
          v_block_table(v_block_number).text := substr(v_lines_table(i).line
                                                      ,regexp_instr(v_lines_table(i).line
                                                                   ,'^'||c_space||'{4}|'||c_tab
                                                                   ,1,1,1
                                                                   )
                                                      );
        else
          /*Text trim all the spaces from the front*/
          v_block_table(v_block_number).text := ltrim(v_lines_table(i).line);
        end if;
        v_block_table(v_block_number).block_type := v_block_type;
      else
        case v_block_type
          when 'B'
          then
            /*Blank line always it's own block*/
            v_block_number := v_block_number + 1;
            v_block_table(v_block_number).text := v_lines_table(i).line;
            v_block_table(v_block_number).block_type := v_block_type;
          when 'C'
          then
            if v_block_table(v_block_number).block_type = 'H'
            then
              /*Code with current block a header start new block*/
              v_block_number := v_block_number + 1;
              v_block_table(v_block_number).text := substr(v_lines_table(i).line
                                                          ,regexp_instr(v_lines_table(i).line
                                                                ,'^'||c_space||'{4}|'||c_tab
                                                                ,1,1,1
                                                                )
                                                          );
              v_block_table(v_block_number).block_type := v_block_type;
            elsif v_block_table(v_block_number).block_type = 'B'
            then             
              if v_block_table.exists(v_block_number-1)
              then
                /*Code current block blank and previous block code
                **then replace the blank block
                **and add the code to the code block
                */
                if v_block_table(v_block_number-1).block_type = 'C'
                then
                  v_block_table.delete(v_block_number);
                  v_block_number := v_block_number - 1;
                  v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                     || c_new_line
                                                     || substr(v_lines_table(i).line
                                                          ,regexp_instr(v_lines_table(i).line
                                                                ,'^'||c_space||'{4}|'||c_tab
                                                                ,1,1,1
                                                                )
                                                              );
                elsif v_block_table(v_block_number-1).block_type in ('O','U')
                then
                  /*Code with current block blank and the previous block a list
                  **Remove the blank block
                  **And add to the list
                  */
                  v_block_table.delete(v_block_number);
                  v_block_number := v_block_number - 1;
                  v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                     || c_new_line || c_new_line
                                                     || substr(v_lines_table(i).line,3);
                else
                  /*Start a new block*/
                  v_block_number := v_block_number+1;
                  v_block_table(v_block_number).text := substr(v_lines_table(i).line
                                                          ,regexp_instr(v_lines_table(i).line
                                                                ,'^'||c_space||'{4}|'||c_tab
                                                                ,1,1,1
                                                                )
                                                          );
                  v_block_table(v_block_number).block_type:= 'C';
                end if;
              end if;
            elsif v_block_table(v_block_number).block_type in ('O','U')  
            then
              /*Current block a list at the line*/
              v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                 || c_new_line
                                                 || substr(v_lines_table(i).line
                                                          ,5
                                                          );
            elsif v_block_table(v_block_number).block_type in ('Q','T')
            then
              /*Current block a quote or text add the line*/
              v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                 || c_new_line
                                                 || v_lines_table(i).line
                                                 ;
            elsif v_block_table(v_block_number).block_type = 'C'
            then
              /*Current block code at the line after removing the 4 spaces or tab*/
              v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                 || c_new_line
                                                 || substr(v_lines_table(i).line
                                                          ,regexp_instr(v_lines_table(i).line
                                                                ,'^'||c_space||'{4}|'||c_tab
                                                                ,1,1,1
                                                                )
                                                          );
            end if;
          when 'O'
          then
            /*Ordered list always start a new block*/
            v_block_number := v_block_number + 1;
            v_block_table(v_block_number).text := substr(v_lines_table(i).line,3);
            v_block_table(v_block_number).block_type := v_block_type;
          when 'U'
          then
            /*Unordered list always start a new block*/
            v_block_number := v_block_number + 1;
            v_block_table(v_block_number).text := substr(v_lines_table(i).line,3);
            v_block_table(v_block_number).block_type := v_block_type;
          when 'Q'
          then
            if v_block_table(v_block_number).block_type in ('Q','O','U')
            then
              /*Current block a quote or a list add the line*/
              if v_block_table(v_block_number).block_type = 'Q'
              then
                v_lines_table(i).line := ltrim(substr(v_lines_table(i).line,2));
              end if;  
              v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                 || c_new_line
                                                 || v_lines_table(i).line
                                                 ;
            elsif v_block_table(v_block_number).block_type in ('C','H')
            then
              /*Current block code or a header start a new block*/
              v_block_number := v_block_number + 1;           
              v_block_table(v_block_number).text := ltrim(substr(v_lines_table(i).line,2));
              v_block_table(v_block_number).block_type := v_block_type;
            else
              if v_block_table.exists(v_block_number-1)
              then
                if  v_block_table(v_block_number-1).block_type = 'Q'
                then
                  /*Current block blank and previous a qoute
                  **remove the blank block and add the line to the quote
                  */
                  v_block_table.delete(v_block_number);
                  v_block_number := v_block_number-1;
                  v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                       || c_new_line|| c_new_line
                                                       || ltrim(substr(v_lines_table(i).line,2));
                  
                else
                  /*Current block blank start previous not a quote
                  **Start a new block
                  */
                  v_block_number := v_block_number + 1;           
                  v_block_table(v_block_number).text := ltrim(substr(v_lines_table(i).line,2));
                  v_block_table(v_block_number).block_type := v_block_type;
                end if;
              else
                /*No previous block start a new block*/
                v_block_number := v_block_number + 1;           
                v_block_table(v_block_number).text := ltrim(substr(v_lines_table(i).line,2));
                v_block_table(v_block_number).block_type := v_block_type;
              end if;
            end if;
          when 'T'
          then
            if v_block_table(v_block_number).block_type in ('Q','O','U','T')
            then
              /*Text and current block a quote, list or text
              **Add the line to the block
              */
              v_block_table(v_block_number).text := v_block_table(v_block_number).text
                                                 || c_new_line
                                                 || ltrim(v_lines_table(i).line)
                                                 ;
            else
              /*Start a new block*/
              v_block_number := v_block_number + 1;           
              v_block_table(v_block_number).text := ltrim(v_lines_table(i).line);
              v_block_table(v_block_number).block_type := v_block_type;
            end if;
        else
          /*Start a new block*/
          v_block_number := v_block_number + 1;           
          v_block_table(v_block_number).text := v_lines_table(i).line;
          v_block_table(v_block_number).block_type := v_block_type;
        end case;
      end if;  
    end loop;
    /*Build the new text back up*/
    v_text := null;
    for k in v_block_table.first .. v_block_table.last
    loop
      if v_block_table(k).block_type not in ('O','U','B')
      then
        /*Check if there is a open list close
        **Close it depending on a unordered or ordered list
        */
        if v_ordered_open
        then
          v_text := v_text||c_new_line||'</ol>'||c_new_line;
          v_ordered_open := false;
        elsif v_unordered_open
        then
          v_text := v_text||c_new_line||'</ul>'||c_new_line;
          v_unordered_open := false;
        end if;
      end if;
      
      if v_block_table(k).block_type = 'B'
      then
        /*Blank line doesn't matter leave it out*/
        null;
      elsif v_block_table(k).block_type = 'C'
      then
        /*Code block escape it first*/
        v_text := v_text||'<pre><code>'||sys.htf.escape_sc(v_block_table(k).text)||c_new_line||'</code></pre>'||c_new_line;
      elsif  v_block_table(k).block_type in ('H','T')
      then
        /*Header or text do all the inline replacement*/
        v_block_table(k).text := replace_bold_italic(v_block_table(k).text);
        v_block_table(k).text := replace_inline_code(v_block_table(k).text);
        v_block_table(k).text := replace_new_line(v_block_table(k).text);
        v_block_table(k).text := replace_image(v_block_table(k).text);
        v_block_table(k).text := replace_link(v_block_table(k).text);
        v_block_table(k).text := replace_references(v_block_table(k).text,v_reference_table);
        if  v_block_table(k).block_type = 'H'
        then
          v_text := v_text||v_block_table(k).text||c_new_line;
        else
          /*If text is in a list and only one line
          **or next block is a list
          **then not a paragraph
          */
          if (v_block_table.first = v_block_table.last
              or
              (v_block_table.first = k
               and
               v_block_table(k+1).block_type in ('O','U')
               )
             ) 
             and
             g_in_list
          then
            v_text := v_text||v_block_table(k).text;
          else
            v_text := v_text||'<p>'||v_block_table(k).text||'</p>'||c_new_line;
          end if;
        end if;
      elsif v_block_table(k).block_type = 'Q'
      then
        v_text := v_text||'<blockquote>'||c_new_line||markdown_to_html(v_block_table(k).text)||c_new_line||'</blockquote>'||c_new_line;
      else
        /*Deteremine of the second level text is rendered normal
        **or as in a list
        */
        if v_block_table.exists(k-1)
        then
          if v_block_table(k-1).block_type = 'B'
          then
            if v_block_table.exists(k-2)
            then
              if v_block_table(k-2).block_type not in  ('O','U')
              then
                g_in_list := true;
              else  
                g_in_list := false;
              end if;
            end if;  
          else  
            g_in_list := true;
          end if;  
        else
          g_in_list := true;
        end if;
        /*Process the text of the list item*/
        v_block_table(k).text := markdown_to_html(v_block_table(k).text);
        g_in_list := false;
        /*Open the list if not already open*/
        if not (v_ordered_open or v_unordered_open)
           and
           v_block_table(k).block_type = 'O'
        then
          v_text := rtrim(v_text,c_new_line)||c_new_line||'<ol>'||c_new_line;
          v_ordered_open := true;
        elsif not (v_unordered_open or v_ordered_open)
              and
              v_block_table(k).block_type = 'U'
        then
          v_text := rtrim(v_text,c_new_line)||c_new_line||'<ul>'||c_new_line;
          v_unordered_open := true;
        end if;
        v_text := v_text||'<li>'||rtrim(v_block_table(k).text,c_new_line)||'</li>'||c_new_line;
      end if;
    end loop;
    /*Close the list if still open*/
    if v_ordered_open
    then
      v_text := v_text||'</ol>';
    elsif v_unordered_open
    then
      v_text := v_text||'</ul>';
    end if;
    return rtrim(ltrim(v_text,c_new_line),c_new_line);
  end markdown_to_html;
  
  function html_to_markdown(p_text in varchar2)
  return varchar2 as
  begin
    /* TODO implementation required */
    return null;
  end html_to_markdown;

end markdown;

/
