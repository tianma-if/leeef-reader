import { useCallback, useState } from 'react'

export type FooterTab = 'none' | 'toc' | 'theme' | 'progress' | 'font'

export function useReaderChrome() {
  const [visible, setVisible] = useState(false)
  const [footerTab, setFooterTab] = useState<FooterTab>('none')
  const [sidebar, setSidebar] = useState(false)

  const hide = useCallback(() => {
    setVisible(false)
    setFooterTab('none')
  }, [])

  const show = useCallback(() => {
    setVisible(true)
  }, [])

  const toggle = useCallback(() => {
    setVisible((current) => {
      if (current) setFooterTab('none')
      return !current
    })
  }, [])

  const openTab = useCallback((tab: FooterTab) => {
    setVisible(true)
    setFooterTab((current) => (current === tab ? 'none' : tab))
    if (tab === 'toc') setSidebar(true)
  }, [])

  const openSidebar = useCallback(() => {
    setSidebar(true)
    setVisible(true)
  }, [])

  const closeSidebar = useCallback(() => {
    setSidebar(false)
    setFooterTab((current) => (current === 'toc' ? 'none' : current))
  }, [])

  return {
    visible,
    footerTab,
    sidebar,
    hide,
    show,
    toggle,
    openTab,
    setFooterTab,
    openSidebar,
    closeSidebar,
  }
}
